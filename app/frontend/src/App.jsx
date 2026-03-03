import { useEffect, useMemo, useState } from "react";
import { fetchHealth, fetchHello, fetchReady, getApiBaseUrl } from "./api/client";
import StatusCard from "./components/StatusCard";
import "./App.css";

function createInitialState() {
  return { loading: true, error: "", data: null };
}

function App() {
  const [hello, setHello] = useState(createInitialState());
  const [health, setHealth] = useState(createInitialState());
  const [ready, setReady] = useState(createInitialState());

  const apiBaseUrl = useMemo(() => getApiBaseUrl(), []);

  useEffect(() => {
    let active = true;

    async function loadEndpoint(loader, setter) {
      try {
        const data = await loader();
        if (!active) return;
        setter({ loading: false, error: "", data });
      } catch (error) {
        if (!active) return;
        setter({
          loading: false,
          error: error instanceof Error ? error.message : "Unexpected API error",
          data: null,
        });
      }
    }

    Promise.all([
      loadEndpoint(fetchHello, setHello),
      loadEndpoint(fetchHealth, setHealth),
      loadEndpoint(fetchReady, setReady),
    ]);

    return () => {
      active = false;
    };
  }, []);

  const allFailed = [hello, health, ready].every((state) => !state.loading && state.error);

  return (
    <main className="page">
      <section className="hero">
        <p className="hero__eyebrow">Cloud-Native Full-Stack Assignment</p>
        <h1>Service Observability Dashboard</h1>
        <p className="hero__subtitle">
          Frontend checks backend liveness, readiness, and API payloads using a configurable base URL.
        </p>
        <p className="hero__meta">
          API Base URL: <code>{apiBaseUrl}</code>
        </p>
      </section>

      {allFailed && (
        <section className="banner banner--error">
          Backend appears unreachable. Verify Flask is running and security groups allow the port.
        </section>
      )}

      <section className="grid">
        <StatusCard title="Hello Endpoint" {...hello} />
        <StatusCard title="Health Check" {...health} />
        <StatusCard title="Readiness Check" {...ready} />
      </section>
    </main>
  );
}

export default App;
