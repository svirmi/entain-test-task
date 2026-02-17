package main

import (
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	app := newApplication()

	port := "8080"
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      app.routes(),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	serverErrors := make(chan error, 1)

	go func() {
		log.Printf("Server listening on :%s (ReadTimeout=%s WriteTimeout=%s IdleTimeout=%s)",
			port, server.ReadTimeout, server.WriteTimeout, server.IdleTimeout)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Server error: %v", err)
		}

	case sig := <-quit:
		log.Printf("\n[shutdown] signal received: %v — beginning graceful shutdown", sig)
	}
}
