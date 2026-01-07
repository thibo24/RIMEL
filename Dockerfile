FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    libfreetype6-dev \
    libpng-dev \
    && rm -rf /var/lib/apt/lists/*


RUN pip install --no-cache-dir requests pandas plotnine

# Copy scripts
COPY . .

CMD ["bash"]
