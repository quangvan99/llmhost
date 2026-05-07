#!/bin/bash
docker ps --filter "name=gemma4-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
