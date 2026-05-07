#!/bin/bash
docker ps --filter "name=llamaembed8b-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
