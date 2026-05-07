#!/bin/bash
docker ps --filter "name=gemma4-fp8-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
