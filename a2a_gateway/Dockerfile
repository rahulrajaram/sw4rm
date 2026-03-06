FROM python:3.11-slim

WORKDIR /app

# Copy SDK and install in editable mode
COPY sdks/py_sdk /app/sdks/py_sdk
RUN pip install --no-cache-dir -e /app/sdks/py_sdk

# Copy gateway requirements and install
COPY a2a_gateway/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy gateway module
COPY a2a_gateway /app/a2a_gateway

# Expose gRPC and HTTP ports
EXPOSE 50054
EXPOSE 8080

# Run the gateway server
CMD ["python", "-m", "a2a_gateway.server"]
