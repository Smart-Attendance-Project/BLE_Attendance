package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

type object map[string]any

type database interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}

type server struct {
	db           *pgxpool.Pool
	contract     apiContract
	secret       []byte
	jwtAlgorithm string
	jwtLifetime  time.Duration
	mux          *http.ServeMux
}

type request struct {
	*http.Request
	db    database
	user  object
	body  any
	query object
	path  object
}

type apiError struct {
	status int
	detail any
	bearer bool
}

func fail(status int, detail string) {
	panic(apiError{status: status, detail: detail})
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func (r *request) args() object {
	return r.body.(object)
}

func (r *request) all(sql string, args ...any) []object {
	rows, err := r.db.Query(r.Context(), sql, args...)
	check(err)
	result, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (object, error) {
		value, err := pgx.RowToMap(row)
		return object(value), err
	})
	check(err)
	return result
}

func (r *request) one(sql string, args ...any) object {
	rows, err := r.db.Query(r.Context(), sql, args...)
	check(err)
	row, err := pgx.CollectOneRow(rows, pgx.RowToMap)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	check(err)
	return object(row)
}

func (r *request) exec(sql string, args ...any) int64 {
	result, err := r.db.Exec(r.Context(), sql, args...)
	check(err)
	return result.RowsAffected()
}

func (r *request) transaction(run func() any) any {
	pool := r.db.(*pgxpool.Pool)
	tx, err := pool.Begin(r.Context())
	check(err)
	defer tx.Rollback(r.Context())
	r.db = tx
	defer func() { r.db = pool }()
	result := run()
	check(tx.Commit(r.Context()))
	return result
}

func textValue(value any) string {
	result, _ := value.(string)
	return result
}

func flag(value any) bool {
	result, _ := value.(bool)
	return result
}

func message(msg string) object {
	return object{"message": msg}
}

func jsonReply(w http.ResponseWriter, status int, value any) {
	body, err := json.Marshal(value)
	check(err)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func plainTextReply(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(body))
}

type download struct {
	data        []byte
	contentType string
	filename    string
}

func (s *server) route(method, path, role string, handler func(*request) any) {
	operation, ok := s.contract.Paths[path][strings.ToLower(method)]
	if !ok {
		panic("route missing from FastAPI contract: " + method + " " + path)
	}
	s.mux.HandleFunc(method+" "+path, func(w http.ResponseWriter, httpRequest *http.Request) {
		r := &request{Request: httpRequest, db: s.db}
		rawBody, hasBody := s.readBody(r, operation)
		if role != "" {
			r.user = s.authenticated(r)
			switch role {
			case "user":
			case "admin":
				if r.user["role"] != role {
					fail(403, "Admin access required")
				}
			default:
				if r.user["role"] != role {
					fail(403, "Forbidden for this role")
				}
			}
		}
		s.validate(r, operation, rawBody, hasBody)
		switch result := handler(r).(type) {
		case download:
			w.Header().Set("Content-Type", result.contentType)
			w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", result.filename))
			_, _ = w.Write(result.data)
		default:
			jsonReply(w, http.StatusOK, result)
		}
	})
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	defer func() {
		switch recovered := recover().(type) {
		case nil:
		case apiError:
			if recovered.bearer {
				w.Header().Set("WWW-Authenticate", "Bearer")
			}
			jsonReply(w, recovered.status, object{"detail": recovered.detail})
		default:
			// Database error details may contain credentials or personal data.
			// Log only the type and the SQLSTATE.
			var pgError *pgconn.PgError
			if err, ok := recovered.(error); ok && errors.As(err, &pgError) {
				slog.Error("request failed", "method", r.Method, "sqlstate", pgError.Code)
			} else {
				slog.Error("request failed", "method", r.Method, "error_type", fmt.Sprintf("%T", recovered))
			}
			plainTextReply(w, http.StatusInternalServerError, "Internal Server Error")
		}
	}()
	if origin := r.Header.Get("Origin"); origin != "" {
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		requestMethod := r.Header.Get("Access-Control-Request-Method")
		if r.Method == http.MethodOptions && requestMethod != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT")
			w.Header().Set("Access-Control-Max-Age", "600")
			if headers := r.Header.Get("Access-Control-Request-Headers"); headers != "" {
				w.Header().Set("Access-Control-Allow-Headers", headers)
			}
			if !strings.Contains(",DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT,", ","+requestMethod+",") {
				plainTextReply(w, http.StatusBadRequest, "Disallowed CORS method")
				return
			}
			plainTextReply(w, http.StatusOK, "OK")
			return
		}
		if r.Header.Get("Cookie") != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
	}
	_, pattern := s.mux.Handler(r)
	if pattern == "" || r.Method == http.MethodHead && strings.HasPrefix(pattern, "GET ") && !isDocsPath(r.URL.Path) {
		if r.URL.Path != "/" && strings.HasSuffix(r.URL.Path, "/") {
			target := r.Clone(r.Context())
			target.URL.Path = strings.TrimSuffix(target.URL.Path, "/")
			if _, match := s.mux.Handler(target); match != "" {
				http.Redirect(w, r, target.URL.String(), http.StatusTemporaryRedirect)
				return
			}
		}
		// ServeMux distinguishes an unknown path from a known path with a
		// different method. Keep the FastAPI JSON error shape in both cases.
		for _, method := range []string{"GET", "POST", "PATCH", "PUT", "DELETE"} {
			probe := r.Clone(r.Context())
			probe.Method = method
			if _, matched := s.mux.Handler(probe); matched != "" {
				w.Header().Set("Allow", method)
				fail(405, "Method Not Allowed")
			}
		}
		fail(404, "Not Found")
	}
	s.mux.ServeHTTP(w, r)
}

func isDocsPath(path string) bool {
	switch path {
	case "/docs", "/redoc", "/docs/oauth2-redirect", "/openapi.json":
		return true
	}
	return false
}

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func databaseURL() string {
	if override := os.Getenv("DATABASE_URL_OVERRIDE"); override != "" {
		return strings.Replace(override, "postgresql+psycopg://", "postgresql://", 1)
	}
	return (&url.URL{
		Scheme: "postgresql",
		User:   url.UserPassword(env("DB_USER", "postgres"), env("DB_PASSWORD", "postgres")),
		Host:   env("DB_HOST", "localhost") + ":" + env("DB_PORT", "5432"),
		Path:   "/" + env("DB_NAME", "ble_attendance"),
	}).String()
}

func run() error {
	if err := godotenv.Load(".env"); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("load .env: %w", err)
	}
	algorithm := env("JWT_ALGORITHM", "HS256")
	if !allowedAlgorithm(algorithm) {
		return errors.New("unsupported JWT_ALGORITHM")
	}
	minutes, err := strconv.Atoi(env("JWT_EXP_MINUTES", "480"))
	if err != nil {
		return fmt.Errorf("read JWT_EXP_MINUTES: %w", err)
	}
	config, err := pgxpool.ParseConfig(databaseURL())
	if err != nil {
		return errors.New("parse PostgreSQL configuration")
	}
	config.MaxConns = 40
	config.MaxConnLifetime = 30 * time.Minute
	config.ConnConfig.ConnectTimeout = 30 * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return errors.New("initialize PostgreSQL pool")
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		return errors.New("connect to PostgreSQL")
	}
	dir := env("ATTENDANCE_WEB_DIR", "build/native")
	if err := initializeSchema(ctx, pool, dir); err != nil {
		return err
	}
	app := &server{
		db: pool, secret: []byte(env("JWT_SECRET", "change-this-in-production")),
		jwtAlgorithm: algorithm, jwtLifetime: time.Duration(minutes) * time.Minute,
		mux: http.NewServeMux(),
	}
	if err := app.docs(dir); err != nil {
		return err
	}
	app.routes()
	address := env("HOST", "0.0.0.0") + ":" + env("PORT", "8000")
	httpServer := &http.Server{Addr: address, Handler: app, ReadHeaderTimeout: 10 * time.Second}
	stopping, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	listen := make(chan error, 1)
	go func() { listen <- httpServer.ListenAndServe() }()
	slog.Info("attendance API listening", "address", address)
	select {
	case err := <-listen:
		return err
	case <-stopping.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		return httpServer.Shutdown(shutdown)
	}
}

func (s *server) docs(dir string) error {
	files := map[string]string{
		"/openapi.json":         "openapi.json",
		"/docs":                 "docs.html",
		"/redoc":                "redoc.html",
		"/docs/oauth2-redirect": "oauth2-redirect.html",
	}
	for endpoint, name := range files {
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		contentType := "text/html; charset=utf-8"
		if endpoint == "/openapi.json" {
			contentType = "application/json"
			if err := json.Unmarshal(data, &s.contract); err != nil {
				return err
			}
		}
		s.mux.HandleFunc("GET "+endpoint, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", contentType)
			_, _ = w.Write(data)
		})
	}
	return nil
}

func initializeSchema(ctx context.Context, pool *pgxpool.Pool, dir string) error {
	schema, err := os.ReadFile(filepath.Join(dir, "schema.sql"))
	if err != nil {
		return err
	}
	if _, err := pool.Exec(ctx, string(schema)); err != nil {
		return errors.New("initialize PostgreSQL schema")
	}
	return nil
}

func main() {
	if err := run(); err != nil {
		slog.Error("attendance API stopped", "error", err)
		os.Exit(1)
	}
}
