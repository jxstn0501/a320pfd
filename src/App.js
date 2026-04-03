import React from 'react';
import './App.css';

const services = [
  {
    title: 'Innenausbau & Trockenbau',
    description:
      'Passgenaue Wände, Decken und Raumlösungen für Wohn- und Gewerbeimmobilien – sauber geplant und präzise ausgeführt.',
  },
  {
    title: 'Akustik & Schallschutz',
    description:
      'Wir verbessern die Raumakustik und reduzieren Lärm mit hochwertigen Akustikdecken und professionellen Schallschutzsystemen.',
  },
  {
    title: 'Brandschutzsysteme',
    description:
      'Geprüfte Brandschutzlösungen nach aktuellen Standards für mehr Sicherheit in privaten und gewerblichen Gebäuden.',
  },
  {
    title: 'Sanierung & Modernisierung',
    description:
      'Von der Teilmodernisierung bis zur vollständigen Sanierung: Wir bringen Ihre Bestandsimmobilie technisch und optisch auf den neuesten Stand.',
  },
];

const processSteps = [
  'Unverbindliche Erstberatung vor Ort oder telefonisch',
  'Transparente Planung inklusive Zeit- und Kostenrahmen',
  'Fachgerechte Umsetzung durch erfahrene Monteure',
  'Saubere Übergabe und Nachbetreuung bei Bedarf',
];

function App() {
  return (
    <div className="site">
      <header className="hero">
        <div className="hero__content">
          <p className="hero__kicker">Trockenbau Schönberger</p>
          <h1>Moderner Trockenbau für Räume mit Zukunft</h1>
          <p className="hero__text">
            Wir realisieren hochwertige Innenausbau-Lösungen mit klarer Kommunikation,
            verlässlichen Terminen und einem starken Blick für Details.
          </p>
          <div className="hero__actions">
            <a className="button button--primary" href="#kontakt">Jetzt Beratung sichern</a>
            <a className="button button--ghost" href="#leistungen">Leistungen ansehen</a>
          </div>
        </div>
      </header>

      <main>
        <section id="leistungen" className="section container">
          <div className="section__intro">
            <h2>Unsere Leistungen</h2>
            <p>
              Effiziente Prozesse, hochwertige Materialien und ein Team mit langjähriger Erfahrung
              im Trockenbau.
            </p>
          </div>
          <div className="card-grid">
            {services.map((service) => (
              <article key={service.title} className="card">
                <h3>{service.title}</h3>
                <p>{service.description}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="section section--muted">
          <div className="container split">
            <div>
              <h2>Warum Schönberger?</h2>
              <p>
                Wir verbinden handwerkliche Qualität mit modernem Projektmanagement. So entstehen
                Ergebnisse, die funktional überzeugen und dauerhaft wertig bleiben.
              </p>
              <ul className="check-list">
                <li>Persönlicher Ansprechpartner während des gesamten Projekts</li>
                <li>Termintreue und transparente Kommunikation</li>
                <li>Saubere Baustellen und strukturierte Abläufe</li>
              </ul>
            </div>
            <div className="badge-box">
              <p className="badge-box__value">15+ Jahre</p>
              <p>Erfahrung im Innenausbau</p>
            </div>
          </div>
        </section>

        <section className="section container">
          <div className="section__intro">
            <h2>So läuft Ihr Projekt ab</h2>
          </div>
          <ol className="timeline">
            {processSteps.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ol>
        </section>

        <section id="kontakt" className="section section--accent">
          <div className="container cta">
            <h2>Bereit für Ihr nächstes Bauprojekt?</h2>
            <p>
              Senden Sie uns Ihre Anfrage – wir melden uns zeitnah mit einer ersten Einschätzung.
            </p>
            <a className="button button--primary" href="mailto:info@trockenbau-schoenberger.de">
              info@trockenbau-schoenberger.de
            </a>
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="container footer__inner">
          <p>© {new Date().getFullYear()} Trockenbau Schönberger</p>
          <p>Innenausbau · Trockenbau · Sanierung</p>
        </div>
      </footer>
    </div>
  );
}

export default App;
