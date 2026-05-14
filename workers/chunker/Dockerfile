FROM golang:1.23-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/chunker ./cmd/chunker

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/chunker /app/chunker
EXPOSE 9101
CMD ["/app/chunker"]
