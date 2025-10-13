# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/devcontainers/python:3.11

WORKDIR /app

# Copy package sources
COPY . .

# Install the package with the langgraph extras
RUN pip install -r requirements.txt

# Expose the port that the agent server uses
EXPOSE 8088

CMD ["python", "langgraph_agent_calculator.py"]
