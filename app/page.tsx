export default function Home() {
  return (
    <div className="space-y-4">
      <h1 className="text-3xl font-semibold">Willkommen zum AI Automations Kurs</h1>
      <p className="text-zinc-700 dark:text-zinc-300">
        In diesem Kurs bauen wir gemeinsam eine moderne Web‑App, verbinden n8n,
        erstellen einen Chat‑ und später Voice‑Agent und automatisieren Blog‑Beiträge.
      </p>
      <div className="rounded-lg border border-zinc-200 p-4 dark:border-zinc-800">
        <h2 className="text-lg font-medium mb-2">Nächste Schritte</h2>
        <ol className="list-decimal ml-5 space-y-1 text-sm">
          <li>
            <code>make setup</code> ausführen und danach Docker starten
          </li>
          <li>Health‑Check: /api/health</li>
          <li>Admin‑Ping: /api/admin/ping mit X-Admin-Token</li>
        </ol>
      </div>
      <div className="rounded-lg border border-zinc-200 p-4 dark:border-zinc-800">
        <h2 className="text-lg font-medium mb-2">Quickstart</h2>
        <pre className="bg-zinc-950 text-zinc-100 text-sm p-3 rounded-md overflow-x-auto">
{`make setup
docker compose --profile dev up -d`}
        </pre>
        <p className="text-xs text-zinc-500 mt-2">
          Das Setup-Skript nutzt die <code>env.template</code> mit ihren <code># @meta</code>-Blöcken,
          schlägt dir Defaults vor und startet danach den optionalen Remote-Switch.
        </p>
      </div>
    </div>
  );
}
