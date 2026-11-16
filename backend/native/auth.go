package main

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	studentIDPattern = regexp.MustCompile(`^D?[0-9]{2}[A-Z]{2,5}[0-9]{3}$`)
	passlibBase64    = base64.NewEncoding("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./").WithPadding(base64.NoPadding)
	ist              = time.FixedZone("IST", 5*3600+30*60)
)

const userFields = "id, full_name, role, student_id, teacher_id, admin_id, COALESCE(is_super_admin, false) AS is_super_admin"

func hashPassword(password string) string {
	salt := make([]byte, 16)
	_, err := rand.Read(salt)
	check(err)
	const rounds = 29000 // Passlib pbkdf2_sha256 default
	key, err := pbkdf2.Key(sha256.New, password, salt, rounds, sha256.Size)
	check(err)
	return fmt.Sprintf("$pbkdf2-sha256$%d$%s$%s", rounds, passlibBase64.EncodeToString(salt), passlibBase64.EncodeToString(key))
}

func verifyPassword(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 5 || parts[0] != "" || parts[1] != "pbkdf2-sha256" {
		return false
	}
	rounds, roundsErr := strconv.Atoi(parts[2])
	salt, saltErr := passlibBase64.DecodeString(parts[3])
	key, keyErr := passlibBase64.DecodeString(parts[4])
	if roundsErr != nil || rounds < 1 || saltErr != nil || keyErr != nil || len(key) != sha256.Size {
		return false
	}
	candidate, err := pbkdf2.Key(sha256.New, password, salt, rounds, sha256.Size)
	return err == nil && subtle.ConstantTimeCompare(candidate, key) == 1
}

func allowedAlgorithm(algorithm string) bool {
	return algorithm == "HS256" || algorithm == "HS384" || algorithm == "HS512"
}

func (s *server) issueToken(subject string) string {
	token := jwt.NewWithClaims(jwt.GetSigningMethod(s.jwtAlgorithm), jwt.RegisteredClaims{
		Subject: subject, ExpiresAt: jwt.NewNumericDate(time.Now().Add(s.jwtLifetime)),
	})
	encoded, err := token.SignedString(s.secret)
	check(err)
	return encoded
}

func (s *server) authenticated(r *request) object {
	scheme, token, _ := strings.Cut(r.Header.Get("Authorization"), " ")
	if !strings.EqualFold(scheme, "bearer") {
		panic(apiError{status: 401, detail: "Not authenticated", bearer: true})
	}
	credentialsError := apiError{status: 401, detail: "Could not validate credentials", bearer: true}
	claims := &jwt.RegisteredClaims{}
	parsed, err := jwt.ParseWithClaims(token, claims, func(*jwt.Token) (any, error) {
		return s.secret, nil
	}, jwt.WithValidMethods([]string{s.jwtAlgorithm}))
	if err != nil || !parsed.Valid || claims.Subject == "" {
		panic(credentialsError)
	}
	user := r.one("SELECT "+userFields+" FROM users WHERE id = $1", claims.Subject)
	if user == nil {
		panic(credentialsError)
	}
	return user
}

func (s *server) login(r *request) any {
	body := r.args()
	user := r.one("SELECT "+userFields+", password_hash FROM users WHERE student_id=$1 OR teacher_id=$1 OR admin_id=$1 LIMIT 1", body["identifier"])
	if user == nil || !verifyPassword(textValue(body["password"]), textValue(user["password_hash"])) {
		fail(401, "Invalid credentials")
	}
	enrollments := []object{}
	if user["role"] == "student" {
		enrollments = r.all("SELECT division_id, batch_id FROM division_students WHERE student_user_id=$1", user["id"])
	}
	ids := make([]int32, 0, len(enrollments))
	for _, enrollment := range enrollments {
		ids = append(ids, enrollment["division_id"].(int32))
	}
	slices.Sort(ids)
	ids = slices.Compact(ids)
	return object{
		"access_token": s.issueToken(textValue(user["id"])), "token_type": "bearer",
		"role": user["role"], "full_name": user["full_name"], "user_id": user["id"],
		"division_ids": ids, "enrollments": enrollments,
	}
}

func createUser(r *request, role string, identifier any, superAdmin bool) object {
	var studentID, teacherID, adminID any
	var duplicate string
	switch role {
	case "student":
		if !studentIDPattern.MatchString(textValue(identifier)) {
			fail(422, "Invalid student ID format")
		}
		studentID, duplicate = identifier, "Student ID already exists"
	case "teacher":
		teacherID, duplicate = identifier, "Teacher ID already exists"
	case "admin":
		adminID, duplicate = identifier, "Admin ID already exists"
	}
	body := r.args()
	user := r.one(`INSERT INTO users (id, full_name, role, student_id, teacher_id, admin_id,
		password_hash, biometric_enabled, is_super_admin, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,false,$8,$9) ON CONFLICT DO NOTHING RETURNING `+userFields,
		uuid.NewString(), body["full_name"], role, studentID, teacherID, adminID,
		hashPassword(textValue(body["password"])), superAdmin, nowUTC())
	if user == nil {
		fail(409, duplicate)
	}
	return user
}

func register(r *request) any {
	body := r.args()
	role := textValue(body["role"])
	if role == "admin" {
		fail(400, "Use admin endpoints to create admin accounts")
	}
	return createUser(r, role, body["identifier"], false)
}

func addStudent(r *request) any {
	return r.transaction(func() any {
		body := r.args()
		student := createUser(r, "student", body["student_id"], false)
		if body["division_id"] != nil && body["division_id"] != int64(0) {
			r.exec("INSERT INTO division_students (student_user_id,division_id,batch_id) VALUES ($1,$2,$3)", student["id"], body["division_id"], body["batch_id"])
		}
		return student
	})
}

func addTeacher(r *request) any {
	return createUser(r, "teacher", r.args()["teacher_id"], false)
}

func addAdmin(r *request) any {
	superAdmin := flag(r.args()["is_super_admin"])
	if superAdmin && !flag(r.user["is_super_admin"]) {
		fail(403, "Only super-admin can create super-admins")
	}
	return createUser(r, "admin", r.args()["admin_id"], superAdmin)
}

func changePassword(r *request) any {
	return r.transaction(func() any {
		password := r.one("SELECT password_hash FROM users WHERE id=$1 FOR UPDATE", r.user["id"])
		body := r.args()
		if !verifyPassword(textValue(body["old_password"]), textValue(password["password_hash"])) {
			fail(400, "Current password is incorrect")
		}
		newPassword := textValue(body["new_password"])
		if utf8.RuneCountInString(newPassword) < 6 {
			fail(422, "New password must be at least 6 characters")
		}
		r.exec("UPDATE users SET password_hash=$2 WHERE id=$1", r.user["id"], hashPassword(newPassword))
		return message("Password changed successfully")
	})
}

func faceProfile(r *request) any {
	data := r.one("SELECT face_embedding FROM users WHERE id=$1", r.user["id"])
	if !truth(data["face_embedding"]) {
		fail(404, "No face profile registered")
	}
	return object{"embedding": data["face_embedding"], "face_registered": true}
}

func storeFace(r *request, reRegister bool) any {
	embedding, _ := r.args()["embedding"].([]any)
	if len(embedding) == 0 {
		fail(422, "embedding must be a list of floats")
	}
	return r.transaction(func() any {
		userID := r.user["id"]
		data := r.one("SELECT face_embedding, face_reg_timestamps FROM users WHERE id=$1 FOR UPDATE", userID)
		existing, _ := data["face_embedding"].([]any)
		var embeddings []any
		if reRegister && len(existing) > 0 {
			primary, ok := existing[0].([]any)
			if !ok {
				primary, existing = existing, []any{existing}
			}
			if len(primary) != len(embedding) {
				fail(422, "Invalid embedding dimensions")
			}
			distance := 0.0
			for i, value := range primary {
				a, validA := numeric(value)
				b, validB := numeric(embedding[i])
				if !validA || !validB {
					panic(fmt.Errorf("stored or supplied face vector is non-numeric"))
				}
				distance += (a - b) * (a - b)
			}
			if math.Sqrt(distance) >= 0.85 {
				fail(400, "Face does not match original profile.")
			}
			embeddings = existing
		}
		embeddings = append(embeddings, embedding)
		timestamps, _ := data["face_reg_timestamps"].([]any)
		timestamps = append(timestamps, time.Now().In(ist).Format("2006-01-02T15:04:05.000000-07:00"))
		r.exec("UPDATE users SET face_embedding=$2, face_reg_timestamps=$3 WHERE id=$1", userID, embeddings, timestamps)
		action := "Face registered"
		if reRegister {
			action = "Face re-registered"
		}
		return object{"message": action, "face_registered": true}
	})
}

func numeric(value any) (float64, bool) {
	switch input := value.(type) {
	case float64:
		return input, true
	case bool:
		if input {
			return 1, true
		}
		return 0, true
	}
	return 0, false
}

func truth(value any) bool {
	switch input := value.(type) {
	case nil:
		return false
	case bool:
		return input
	case float64:
		return input != 0
	case string:
		return input != ""
	case []any:
		return len(input) > 0
	case map[string]any:
		return len(input) > 0
	}
	return true
}
