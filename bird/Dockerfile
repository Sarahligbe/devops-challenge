FROM golang:1.22.5-alpine AS build

RUN addgroup -S birdgroup && adduser -S birduser -G birdgroup

WORKDIR /bird

COPY go.mod ./

RUN go mod download

COPY *.go ./

RUN go build -o getBird

FROM scratch

WORKDIR /bird

# Copy binary from build stage
COPY --from=build /bird/getBird .

# Copy the non-root user
COPY --from=build /etc/passwd /etc/passwd

EXPOSE 4201

ENTRYPOINT ["./getBird"]