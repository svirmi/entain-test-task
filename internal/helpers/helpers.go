package helpers

import (
	"encoding/json"
	"net/http"
)

func ValidSourceTypes() map[string]bool {
	validSourceTypes := map[string]bool{"game": true, "server": true, "payment": true}

	return validSourceTypes
}

func WriteJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func WriteError(w http.ResponseWriter, status int, message string) {
	WriteJSON(w, status, map[string]string{"error": message})
}
