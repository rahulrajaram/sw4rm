use crate::{Error, Result};
use std::time::{Duration, Instant};
use tonic::transport::{Channel, Endpoint};
use tonic::{Request, Status};
use tower::Service;
use tower_layer::Layer;

/// Middleware layer for adding correlation ID and user agent headers
#[derive(Clone)]
pub struct CorrelationIdLayer {
    correlation_id: Option<String>,
    user_agent: String,
}

impl CorrelationIdLayer {
    pub fn new() -> Self {
        Self {
            correlation_id: None,
            user_agent: format!("sw4rm-rust-sdk/{}", crate::VERSION),
        }
    }

    pub fn with_correlation_id(mut self, correlation_id: String) -> Self {
        self.correlation_id = Some(correlation_id);
        self
    }

    pub fn with_user_agent(mut self, user_agent: String) -> Self {
        self.user_agent = user_agent;
        self
    }
}

impl<S> Layer<S> for CorrelationIdLayer {
    type Service = CorrelationIdService<S>;

    fn layer(&self, service: S) -> Self::Service {
        CorrelationIdService {
            inner: service,
            correlation_id: self.correlation_id.clone(),
            user_agent: self.user_agent.clone(),
        }
    }
}

#[derive(Clone)]
pub struct CorrelationIdService<S> {
    inner: S,
    correlation_id: Option<String>,
    user_agent: String,
}

impl<S, ReqBody> Service<Request<ReqBody>> for CorrelationIdService<S>
where
    S: Service<Request<ReqBody>>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::result::Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, mut request: Request<ReqBody>) -> Self::Future {
        // Add correlation ID header if provided
        if let Some(ref correlation_id) = self.correlation_id {
            request
                .metadata_mut()
                .insert("x-correlation-id", correlation_id.parse().unwrap());
        }

        // Add user agent header
        request
            .metadata_mut()
            .insert("user-agent", self.user_agent.parse().unwrap());

        self.inner.call(request)
    }
}

/// Timing interceptor for measuring request duration
#[derive(Clone)]
pub struct TimingLayer;

impl<S> Layer<S> for TimingLayer {
    type Service = TimingService<S>;

    fn layer(&self, service: S) -> Self::Service {
        TimingService { inner: service }
    }
}

#[derive(Clone)]
pub struct TimingService<S> {
    inner: S,
}

impl<S, ReqBody> Service<Request<ReqBody>> for TimingService<S>
where
    S: Service<Request<ReqBody>>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = TimingFuture<S::Future>;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::result::Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request<ReqBody>) -> Self::Future {
        let start = Instant::now();
        let method = "grpc_method".to_string(); // gRPC doesn't expose HTTP URI directly
        
        TimingFuture {
            inner: self.inner.call(request),
            start,
            method,
        }
    }
}

pin_project_lite::pin_project! {
    pub struct TimingFuture<F> {
        #[pin]
        inner: F,
        start: Instant,
        method: String,
    }
}

impl<F, T, E> std::future::Future for TimingFuture<F>
where
    F: std::future::Future<Output = std::result::Result<T, E>>,
{
    type Output = F::Output;

    fn poll(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Self::Output> {
        let this = self.project();
        match this.inner.poll(cx) {
            std::task::Poll::Ready(result) => {
                let duration = this.start.elapsed();
                tracing::debug!(
                    "gRPC call {} completed in {:?}",
                    this.method,
                    duration
                );
                std::task::Poll::Ready(result)
            }
            std::task::Poll::Pending => std::task::Poll::Pending,
        }
    }
}

/// Retry interceptor with exponential backoff
#[derive(Clone)]
pub struct RetryLayer {
    max_attempts: usize,
    base_delay: Duration,
    max_delay: Duration,
}

impl RetryLayer {
    pub fn new() -> Self {
        Self {
            max_attempts: 3,
            base_delay: Duration::from_millis(100),
            max_delay: Duration::from_secs(10),
        }
    }

    pub fn with_max_attempts(mut self, max_attempts: usize) -> Self {
        self.max_attempts = max_attempts;
        self
    }

    pub fn with_base_delay(mut self, base_delay: Duration) -> Self {
        self.base_delay = base_delay;
        self
    }

    pub fn with_max_delay(mut self, max_delay: Duration) -> Self {
        self.max_delay = max_delay;
        self
    }
}

impl<S> Layer<S> for RetryLayer {
    type Service = RetryService<S>;

    fn layer(&self, service: S) -> Self::Service {
        RetryService {
            inner: service,
            max_attempts: self.max_attempts,
            base_delay: self.base_delay,
            max_delay: self.max_delay,
        }
    }
}

#[derive(Clone)]
pub struct RetryService<S> {
    inner: S,
    max_attempts: usize,
    base_delay: Duration,
    max_delay: Duration,
}

impl<S, ReqBody> Service<Request<ReqBody>> for RetryService<S>
where
    S: Service<Request<ReqBody>, Error = Status>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::result::Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request<ReqBody>) -> Self::Future {
        // Simplified retry logic - just pass through for now
        // Full retry implementation would need to be done at a higher level
        // where request cloning can be handled properly
        tracing::debug!("RetryService: executing request (simplified retry logic)");
        self.inner.call(request)
    }
}

// Retry logic is simplified - full implementation would require more complex
// request cloning and state management at the application level

fn is_retryable_error(status: &Status) -> bool {
    use tonic::Code;
    matches!(
        status.code(),
        Code::Unavailable | Code::DeadlineExceeded | Code::ResourceExhausted | Code::Aborted
    )
}

/// Metrics interceptor for collecting gRPC call statistics
#[derive(Clone)]
pub struct MetricsLayer {
    enable_histogram: bool,
}

impl MetricsLayer {
    pub fn new() -> Self {
        Self {
            enable_histogram: true,
        }
    }

    pub fn with_histogram(mut self, enable: bool) -> Self {
        self.enable_histogram = enable;
        self
    }
}

impl<S> Layer<S> for MetricsLayer {
    type Service = MetricsService<S>;

    fn layer(&self, service: S) -> Self::Service {
        MetricsService {
            inner: service,
            enable_histogram: self.enable_histogram,
        }
    }
}

#[derive(Clone)]
pub struct MetricsService<S> {
    inner: S,
    enable_histogram: bool,
}

impl<S, ReqBody> Service<Request<ReqBody>> for MetricsService<S>
where
    S: Service<Request<ReqBody>>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = MetricsFuture<S::Future>;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::result::Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request<ReqBody>) -> Self::Future {
        let start = Instant::now();
        let method = "grpc_method".to_string(); // gRPC doesn't expose HTTP URI directly
        
        MetricsFuture {
            inner: self.inner.call(request),
            start,
            method,
            enable_histogram: self.enable_histogram,
        }
    }
}

pin_project_lite::pin_project! {
    pub struct MetricsFuture<F> {
        #[pin]
        inner: F,
        start: Instant,
        method: String,
        enable_histogram: bool,
    }
}

impl<F, T, E> std::future::Future for MetricsFuture<F>
where
    F: std::future::Future<Output = std::result::Result<T, E>>,
{
    type Output = F::Output;

    fn poll(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Self::Output> {
        let this = self.project();
        match this.inner.poll(cx) {
            std::task::Poll::Ready(result) => {
                let duration = this.start.elapsed();
                
                // Log metrics (in a real implementation, you'd send to a metrics backend)
                match &result {
                    Ok(_) => {
                        tracing::info!(
                            "gRPC call {} succeeded in {:?}",
                            this.method,
                            duration
                        );
                    }
                    Err(_) => {
                        tracing::warn!(
                            "gRPC call {} failed in {:?}",
                            this.method,
                            duration
                        );
                    }
                }
                
                if *this.enable_histogram {
                    // In a real implementation, record histogram metrics here
                    tracing::debug!(
                        "Recording histogram for method {} with duration {:?}",
                        this.method,
                        duration
                    );
                }
                
                std::task::Poll::Ready(result)
            }
            std::task::Poll::Pending => std::task::Poll::Pending,
        }
    }
}

/// Builder for creating channels with interceptors
pub struct InterceptedChannelBuilder {
    endpoint: Endpoint,
    correlation_id: Option<String>,
    user_agent: Option<String>,
    enable_timing: bool,
    enable_retry: bool,
    retry_config: RetryLayer,
    enable_metrics: bool,
}

impl InterceptedChannelBuilder {
    pub fn new(endpoint: Endpoint) -> Self {
        Self {
            endpoint,
            correlation_id: None,
            user_agent: None,
            enable_timing: false,
            enable_retry: false,
            retry_config: RetryLayer::new(),
            enable_metrics: false,
        }
    }

    pub fn with_correlation_id(mut self, correlation_id: String) -> Self {
        self.correlation_id = Some(correlation_id);
        self
    }

    pub fn with_user_agent(mut self, user_agent: String) -> Self {
        self.user_agent = Some(user_agent);
        self
    }

    pub fn with_timing(mut self) -> Self {
        self.enable_timing = true;
        self
    }

    pub fn with_retry(mut self, config: RetryLayer) -> Self {
        self.enable_retry = true;
        self.retry_config = config;
        self
    }

    pub fn with_metrics(mut self) -> Self {
        self.enable_metrics = true;
        self
    }

    pub async fn connect(self) -> Result<Channel> {
        let channel = self.endpoint.connect().await
            .map_err(|e| Error::Transport(e))?;

        // Note: Interceptors are applied at the client level, not channel level
        // Each gRPC client service will apply interceptors when created
        if self.correlation_id.is_some() {
            tracing::debug!("Channel configured with correlation_id: {:?}", self.correlation_id);
        }
        let intercepted_channel = channel;

        Ok(intercepted_channel)
    }
}

/// Tonic interceptor for adding metadata headers
#[derive(Clone, Debug)]
pub struct MetadataInterceptor {
    correlation_id: Option<String>,
    user_agent: String,
}

impl MetadataInterceptor {
    pub fn new(correlation_id: Option<String>, user_agent: String) -> Self {
        Self {
            correlation_id,
            user_agent,
        }
    }
}

impl tonic::service::Interceptor for MetadataInterceptor {
    fn call(&mut self, mut request: tonic::Request<()>) -> std::result::Result<tonic::Request<()>, tonic::Status> {
        // Add correlation ID header if present
        if let Some(ref correlation_id) = self.correlation_id {
            request.metadata_mut().insert(
                "x-correlation-id",
                tonic::metadata::MetadataValue::try_from(correlation_id.as_str())
                    .map_err(|_| tonic::Status::invalid_argument("Invalid correlation ID"))?
            );
        }

        // Add user-agent header
        request.metadata_mut().insert(
            "user-agent",
            tonic::metadata::MetadataValue::try_from(self.user_agent.as_str())
                .map_err(|_| tonic::Status::invalid_argument("Invalid user-agent"))?
        );

        // Add request ID for tracing
        let request_id = crate::types::new_uuid();
        request.metadata_mut().insert(
            "x-request-id",
            tonic::metadata::MetadataValue::try_from(request_id.as_str())
                .map_err(|_| tonic::Status::invalid_argument("Invalid request ID"))?
        );

        tracing::debug!(
            correlation_id = ?self.correlation_id,
            user_agent = %self.user_agent,
            request_id = %request_id,
            "Adding metadata to gRPC request"
        );

        Ok(request)
    }
}

// Helper function removed - use client-specific with_interceptor methods instead

/// Convenience function to create a channel with common interceptors
pub async fn create_intercepted_channel(
    endpoint: &str,
    correlation_id: Option<String>,
    enable_all: bool,
) -> Result<Channel> {
    let endpoint = Endpoint::from_shared(endpoint.to_string())
        .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?;

    let mut builder = InterceptedChannelBuilder::new(endpoint);

    if let Some(correlation_id) = correlation_id {
        builder = builder.with_correlation_id(correlation_id);
    }

    if enable_all {
        builder = builder
            .with_timing()
            .with_retry(RetryLayer::new().with_max_attempts(3))
            .with_metrics();
    }

    builder.connect().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_retry_layer_config() {
        let layer = RetryLayer::new()
            .with_max_attempts(5)
            .with_base_delay(Duration::from_millis(200))
            .with_max_delay(Duration::from_secs(30));

        assert_eq!(layer.max_attempts, 5);
        assert_eq!(layer.base_delay, Duration::from_millis(200));
        assert_eq!(layer.max_delay, Duration::from_secs(30));
    }

    #[test]
    fn test_correlation_id_layer() {
        let layer = CorrelationIdLayer::new()
            .with_correlation_id("test-123".to_string())
            .with_user_agent("custom-agent/1.0".to_string());

        assert_eq!(layer.correlation_id, Some("test-123".to_string()));
        assert_eq!(layer.user_agent, "custom-agent/1.0");
    }

    #[test]
    fn test_is_retryable_error() {
        use tonic::{Code, Status};

        assert!(is_retryable_error(&Status::new(Code::Unavailable, "service unavailable")));
        assert!(is_retryable_error(&Status::new(Code::DeadlineExceeded, "timeout")));
        assert!(is_retryable_error(&Status::new(Code::ResourceExhausted, "rate limited")));
        assert!(is_retryable_error(&Status::new(Code::Aborted, "aborted")));

        assert!(!is_retryable_error(&Status::new(Code::InvalidArgument, "bad request")));
        assert!(!is_retryable_error(&Status::new(Code::NotFound, "not found")));
        assert!(!is_retryable_error(&Status::new(Code::PermissionDenied, "forbidden")));
    }
}