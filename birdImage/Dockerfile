FROM golang:1.22.5-alpine AS build

RUN addgroup -S birdgroup && adduser -S birduser -G birdgroup

WORKDIR /birdImage

COPY go.mod ./

RUN go mod download

COPY *.go ./

RUN go build -o getBirdImage

FROM scratch

WORKDIR /birdImage

# Copy binary from build stage
COPY --from=build /birdImage/getBirdImage .

# Copy the non-root user
COPY --from=build /etc/passwd /etc/passwd

EXPOSE 4201

ENTRYPOINT ["./getBirdImage"]