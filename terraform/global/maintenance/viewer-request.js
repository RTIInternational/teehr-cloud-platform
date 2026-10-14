// Browsers get the maintenance page; API clients (Spark, scripts, the
// dashboards' fetches) get a JSON 503 so they fail with a readable error.
function handler(event) {
  var request = event.request;
  var host = request.headers.host ? request.headers.host.value : "";
  var accept = request.headers.accept ? request.headers.accept.value : "";

  if (request.uri === "/status.json") {
    return request;
  }

  var isPageRequest =
    (request.method === "GET" || request.method === "HEAD") &&
    accept.indexOf("text/html") !== -1;

  if (host.indexOf("status.") === 0 || isPageRequest) {
    request.uri = "/index.html";
    return request;
  }

  return {
    statusCode: 503,
    statusDescription: "Service Unavailable",
    headers: {
      "content-type": { value: "application/json" },
      "cache-control": { value: "no-store" },
      "retry-after": { value: "3600" },
    },
    body: {
      encoding: "text",
      data: JSON.stringify({
        status: 503,
        detail: "TEEHR is down for maintenance. See https://status.teehr.rtiamanzi.org",
      }),
    },
  };
}
