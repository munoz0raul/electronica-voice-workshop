# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved.
#
# Minimal fleet status page for the VENTUNO Q. Standard library only; no pip
# dependencies.
FROM python:3.12-slim

COPY status_page/ /app/status_page/
WORKDIR /app

EXPOSE 8081
CMD ["python", "-u", "status_page/server.py"]
