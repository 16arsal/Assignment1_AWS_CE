const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL?.trim() || "/api").replace(/\/$/, "");

async function request(path) {
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  const response = await fetch(`${API_BASE_URL}${normalizedPath}`);

  if (!response.ok) {
    throw new Error(`${path} failed (${response.status})`);
  }

  return response.json();
}

export function getApiBaseUrl() {
  return API_BASE_URL;
}

export function fetchHello() {
  return request("/hello");
}

export function fetchHealth() {
  return request("/health");
}

export function fetchReady() {
  return request("/ready");
}
