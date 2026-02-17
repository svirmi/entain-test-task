package main

import "net/http"

func (app *application) logRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		sourceType := r.Header.Get("Source-Type")
		ip := r.RemoteAddr
		uri := r.URL.RequestURI()

		app.logger.Info("received request", "source-type", sourceType, "ip", ip, "uri", uri)
		next.ServeHTTP(w, r)
	})
}
