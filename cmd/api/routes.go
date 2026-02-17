package main

import "net/http"

func (app *application) routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", app.healthCheck)
	mux.HandleFunc("POST /user/{userId}/transaction", app.createTransaction)
	mux.HandleFunc("GET /user/{userId}/balance", app.getUserBalance)

	return app.logRequest(mux)
}
