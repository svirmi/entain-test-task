package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/svirmi/entain-test-task/internal/helpers"
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

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	// graceful shutdown routines

	select {
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			app.logger.Error("server error", "error", err)
			os.Exit(1)
		}

	case sig := <-quit:
		app.logger.Info("shutdown signal received", "signal", sig.String())

		shutdownTimeout := helpers.GetEnvAsDuration("SHUTDOWN_TIMEOUT", 30*time.Second)
		ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()

		// Step 1 — stop accepting new connections.
		app.logger.Info("shutdown step 1/3: stopping HTTP listener", "timeout", shutdownTimeout)
		if err := server.Shutdown(ctx); err != nil {
			app.logger.Warn("server.Shutdown error, forcing Close", "error", err)
			_ = server.Close()
		}
		app.logger.Info("shutdown step 1/3: HTTP listener stopped")

		// Step 2 — drain in-flight handlers
		app.logger.Info("shutdown step 2/3: draining in-flight requests")
		waitDone := make(chan struct{})
		go func() { app.wg.Wait(); close(waitDone) }()

		select {
		case <-waitDone:
			app.logger.Info("shutdown step 2/3: all requests completed")
		case <-ctx.Done():
			app.logger.Warn("shutdown step 2/3: timeout reached, some requests interrupted")
		}

		// Step 3 — close DB pool
		app.logger.Info("shutdown step 3/3: closing database pool")
		if err := app.db.Close(); err != nil {
			app.logger.Error("db.Close error", "error", err)
		} else {
			app.logger.Info("shutdown step 3/3: database pool closed")
		}

		app.logger.Info("shutdown complete")
	}
}
