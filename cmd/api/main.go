// file cmd/api/main.go

package main

import (
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/lib/pq"
)

func main() {

	app, err := newApplication()

	if err != nil {
		os.Stderr.WriteString("startup error: " + err.Error() + "\n")
		os.Exit(1)
	}

	port := app.config.port
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      app.routes(),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	serverErrors := make(chan error, 1)

	go func() {
		app.logger.Info("server started",
			"addr", server.Addr,
			"env", app.config.env,
			"readTimeout", server.ReadTimeout,
			"writeTimeout", server.WriteTimeout,
		)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			app.logger.Error("server error", "error", err)
			os.Exit(1)
		}

	case sig := <-quit:
		app.logger.Info("shutdown signal received", "signal", sig.String())
	}
}
