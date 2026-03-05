const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL?.replace(/\/$/, "") || "http://localhost:5000";

async function request(path) {
  const response = await fetch(`${API_BASE_URL}${path}`);

  if (!response.ok) {
    throw new Error(`${path} failed (${response.status})`);
  }

  return response.json();
}

export function getApiBaseUrl() {
  return API_BASE_URL;
}

export function fetchHello() {
  return request("/api/hello");
}

export function fetchHealth() {
  return request("/health");
}

export function fetchReady() {
  return request("/ready");
}
