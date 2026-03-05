function StatusCard({ title, loading, error, data }) {
  return (
    <section className="status-card">
      <header className="status-card__header">
        <h2>{title}</h2>
      </header>

      {loading && <p className="status-card__loading">Loading...</p>}
      {!loading && error && <p className="status-card__error">{error}</p>}
      {!loading && !error && <pre>{JSON.stringify(data, null, 2)}</pre>}
    </section>
  );
}

export default StatusCard;
