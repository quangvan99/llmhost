#!/bin/bash
docker ps --filter "name=nemotron4b-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
