#!/bin/bash
if [ -n "$PROJECT_GIT_URL" ]; then
    mkdir -p "$PROJECT_DIR"
    echo "Removing $PROJECT_DIR"
    [ -d "$PROJECT_DIR" ] && rm -rf "$PROJECT_DIR"
    sleep $(( RANDOM % 3 + RANDOM % 5 ))
    echo "Running: git clone -b $PROJECT_GIT_BRANCH $PROJECT_GIT_URL $PROJECT_DIR"
    git clone -b "$PROJECT_GIT_BRANCH" "$PROJECT_GIT_URL" "$PROJECT_DIR"
    if [ $? -eq 0 ]; then
        echo "Clone successful."
    else
        echo "Clone failed."
        exit 1
    fi
    apach2ctl restart
fi