package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"
)

type apiContract struct {
	Paths      map[string]map[string]operation
	Components struct {
		Schemas map[string]schema
	}
}

type operation struct {
	Parameters []struct {
		Name     string
		In       string
		Required bool
		Schema   schema
	}
	RequestBody *struct {
		Content map[string]struct{ Schema schema }
	}
}

type schema struct {
	Reference  string `json:"$ref"`
	Type       string
	Properties fields
	Required   []string
	AnyOf      []schema
	Items      *schema
	Default    any
	Enum       []string
	MinLength  int
	MaxLength  int
}

type fields []struct {
	name   string
	schema schema
}

func (f *fields) UnmarshalJSON(data []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	if _, err := decoder.Token(); err != nil {
		return err
	}
	for decoder.More() {
		key, err := decoder.Token()
		if err != nil {
			return err
		}
		var definition schema
		if err := decoder.Decode(&definition); err != nil {
			return err
		}
		*f = append(*f, struct {
			name   string
			schema schema
		}{key.(string), definition})
	}
	_, err := decoder.Token()
	return err
}

func validationError(kind string, location []any, message string, input any) object {
	return object{"type": kind, "loc": location, "msg": message, "input": input}
}

func (s *server) readBody(r *request, op operation) (any, bool) {
	if op.RequestBody == nil {
		return nil, false
	}
	data, err := io.ReadAll(r.Body)
	if err != nil {
		fail(http.StatusBadRequest, "There was an error parsing the body")
	}
	if len(data) == 0 {
		return nil, false
	}
	contentType := r.Header.Get("Content-Type")
	mediaType, _, _ := mime.ParseMediaType(contentType)
	if contentType != "" && mediaType != "application/json" &&
		!(strings.HasPrefix(mediaType, "application/") && strings.HasSuffix(mediaType, "+json")) {
		return string(data), true
	}
	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		var syntax *json.SyntaxError
		var offset int64
		if errors.As(err, &syntax) {
			offset = syntax.Offset - 1
			if syntax.Error() == "unexpected end of JSON input" {
				offset = int64(len(data))
			}
		}
		issue := validationError("json_invalid", []any{"body", offset}, "JSON decode error", object{})
		issue["ctx"] = object{"error": "Invalid JSON"}
		panic(apiError{status: 422, detail: []object{issue}})
	}
	return value, true
}

func (s *server) validate(r *request, op operation, rawBody any, hasBody bool) {
	r.path, r.query = object{}, object{}
	var issues []object
	for _, parameter := range op.Parameters {
		location := []any{parameter.In, parameter.Name}
		var raw string
		if parameter.In == "path" {
			raw = r.PathValue(parameter.Name)
		} else {
			values := r.URL.Query()[parameter.Name]
			if len(values) == 0 {
				if parameter.Required {
					issues = append(issues, validationError("missing", location, "Field required", nil))
				}
				continue
			}
			raw = values[len(values)-1]
		}
		value := s.convert(parameter.Schema, raw, location, &issues)
		if parameter.In == "path" {
			r.path[parameter.Name] = value
		} else {
			r.query[parameter.Name] = value
		}
	}
	if op.RequestBody != nil {
		if !hasBody || rawBody == nil {
			issues = append(issues, validationError("missing", []any{"body"}, "Field required", nil))
		} else {
			r.body = s.convert(op.RequestBody.Content["application/json"].Schema, rawBody, []any{"body"}, &issues)
		}
	}
	if len(issues) > 0 {
		panic(apiError{status: 422, detail: issues})
	}
}

func (s *server) convert(def schema, value any, path []any, issues *[]object) any {
	if def.Reference != "" {
		def = s.contract.Components.Schemas[strings.TrimPrefix(def.Reference, "#/components/schemas/")]
	}
	if len(def.AnyOf) > 0 {
		if value == nil {
			return nil
		}
		return s.convert(def.AnyOf[0], value, path, issues)
	}
	report := func(kind, message string) object {
		issue := validationError(kind, path, message, value)
		*issues = append(*issues, issue)
		return issue
	}
	switch def.Type {
	case "object":
		input, ok := value.(map[string]any)
		if !ok {
			if def.Properties != nil {
				report("model_attributes_type", "Input should be a valid dictionary or object to extract fields from")
			} else {
				report("dict_type", "Input should be a valid dictionary")
			}
			return nil
		}
		if def.Properties == nil {
			return object(input)
		}
		result := object{}
		for _, field := range def.Properties {
			childPath := appendPath(path, field.name)
			if item, exists := input[field.name]; exists {
				result[field.name] = s.convert(field.schema, item, childPath, issues)
			} else if contains(def.Required, field.name) {
				*issues = append(*issues, validationError("missing", childPath, "Field required", value))
			} else {
				result[field.name] = field.schema.Default
			}
		}
		return result
	case "array":
		input, ok := value.([]any)
		if !ok {
			report("list_type", "Input should be a valid list")
			return nil
		}
		output := make([]any, len(input))
		for index, item := range input {
			output[index] = s.convert(*def.Items, item, appendPath(path, index), issues)
		}
		return output
	case "string":
		input, ok := value.(string)
		if len(def.Enum) > 0 && (!ok || !contains(def.Enum, input)) {
			options := "'" + strings.Join(def.Enum[:len(def.Enum)-1], "', '") + "' or '" + def.Enum[len(def.Enum)-1] + "'"
			issue := report("enum", "Input should be "+options)
			issue["ctx"] = object{"expected": options}
			return nil
		}
		if !ok {
			report("string_type", "Input should be a valid string")
			return nil
		}
		length := utf8.RuneCountInString(input)
		if length < def.MinLength {
			issue := report("string_too_short", fmt.Sprintf("String should have at least %d characters", def.MinLength))
			issue["ctx"] = object{"min_length": def.MinLength}
		}
		if def.MaxLength > 0 && length > def.MaxLength {
			issue := report("string_too_long", fmt.Sprintf("String should have at most %d characters", def.MaxLength))
			issue["ctx"] = object{"max_length": def.MaxLength}
		}
	case "integer":
		switch input := value.(type) {
		case float64:
			if input == float64(int64(input)) {
				return int64(input)
			}
			report("int_from_float", "Input should be a valid integer, got a number with a fractional part")
		case bool:
			if input {
				return int64(1)
			}
			return int64(0)
		case string:
			if result, err := strconv.ParseInt(strings.TrimSpace(input), 10, 64); err == nil {
				return result
			}
			if whole, suffix, found := strings.Cut(strings.TrimSpace(input), "."); found && suffix != "" && strings.Trim(suffix, "0") == "" {
				if result, err := strconv.ParseInt(whole, 10, 64); err == nil {
					return result
				}
			}
			report("int_parsing", "Input should be a valid integer, unable to parse string as an integer")
		default:
			report("int_type", "Input should be a valid integer")
		}
	case "boolean":
		switch input := value.(type) {
		case bool:
			return input
		case string:
			switch strings.ToLower(input) {
			case "1", "on", "t", "true", "y", "yes":
				return true
			case "0", "off", "f", "false", "n", "no":
				return false
			}
			report("bool_parsing", "Input should be a valid boolean, unable to interpret input")
		case float64:
			if input == 0 || input == 1 {
				return input == 1
			}
			report("bool_parsing", "Input should be a valid boolean, unable to interpret input")
		default:
			report("bool_type", "Input should be a valid boolean")
		}
	}
	return value
}

func appendPath(path []any, component any) []any {
	extended := make([]any, len(path)+1)
	copy(extended, path)
	extended[len(path)] = component
	return extended
}

func contains(values []string, value string) bool {
	for _, item := range values {
		if item == value {
			return true
		}
	}
	return false
}
