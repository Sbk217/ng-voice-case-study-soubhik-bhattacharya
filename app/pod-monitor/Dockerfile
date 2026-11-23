FROM golang:1.27.3 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /pod-monitor

FROM gcr.io/distroless/static:nonroot
COPY --from=build /pod-monitor /pod-monitor
USER nonroot:nonroot
ENTRYPOINT ["/pod-monitor"]

