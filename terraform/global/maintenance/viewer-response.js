// The page itself is a 200 from S3; report it as a 503 on app hosts so
// monitors and crawlers see an outage. status.<zone> stays a 200.
function handler(event) {
  var request = event.request;
  var response = event.response;
  var host = request.headers.host ? request.headers.host.value : "";

  if (host.indexOf("status.") === 0 || request.uri === "/status.json") {
    return response;
  }

  if (response.statusCode === 200) {
    response.statusCode = 503;
    response.statusDescription = "Service Unavailable";
    response.headers["retry-after"] = { value: "3600" };
    response.headers["cache-control"] = { value: "no-store" };
  }
  return response;
}
