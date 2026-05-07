#!/bin/bash
docker ps --filter "name=qwen35b-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
