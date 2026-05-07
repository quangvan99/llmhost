#!/bin/bash
docker ps --filter "name=nemotron3nano-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
