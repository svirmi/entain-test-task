package helpers

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strconv"
	"time"
)

func ValidSourceTypes() map[string]bool {
	validSourceTypes := map[string]bool{"game": true, "server": true, "payment": true}

	return validSourceTypes
}

// extracts and validates the {userId} path parameter.
func ParseUserID(r *http.Request) (uint64, error) {
	raw := r.PathValue("userId")
	id, err := strconv.ParseUint(raw, 10, 64)
	if err != nil || id == 0 {
		return 0, errors.New("invalid user id")
	}
	return id, nil
}

func ParseAndFormat(value string) (string, error) {
	rat, ok := NewRat(value)
	if !ok {
		return "", fmt.Errorf("invalid decimal value: %q", value)
	}
	return RatToDecimal(rat), nil
}

func RatToDecimal(r *big.Rat) string {
	f, _ := r.Float64()
	return fmt.Sprintf("%.2f", f)
}

func NewRat(s string) (*big.Rat, bool) {
	return new(big.Rat).SetString(s)
}

func WriteJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func WriteError(w http.ResponseWriter, status int, message string) {
	WriteJSON(w, status, map[string]string{"error": message})
}

func GetEnvAsStr(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}

func GetEnvAsDuration(key string, defaultValue time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return defaultValue
}
