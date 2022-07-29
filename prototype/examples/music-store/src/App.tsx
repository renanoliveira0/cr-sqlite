import { DB, Notifier } from "./createDb";
import { createSignal, For, Show } from "solid-js";

const prompt = "sql> ";
const [commands, setCommands] = createSignal<string[]>([]);

export default function App({ db, notifier }: { db: DB; notifier: Notifier }) {
  return <Term db={db} notifier={notifier} />;
}

function Term({ db, notifier }: { db: DB; notifier: Notifier }) {
  return (
    <div class="term">
      <Output db={db} notifier={notifier} />
      <Input />
    </div>
  );
}

function Output({ db, notifier }: { db: DB; notifier: Notifier }) {
  return (
    <div class="output">
      <For each={commands()}>
        {(cmd, i) => <Cell cmd={cmd} db={db} notifier={notifier} />}
      </For>
    </div>
  );
}

function Cell({
  cmd,
  db,
  notifier,
}: {
  cmd: string;
  db: DB;
  notifier: Notifier;
}) {
  return (
    <div>
      <div>
        {prompt}
        {cmd}
      </div>
      <div>
        <DBResult cmd={cmd} db={db} notifier={notifier} />
      </div>
    </div>
  );
}

function DBResult({
  cmd,
  db,
  notifier,
}: {
  cmd: string;
  db: DB;
  notifier: Notifier;
}) {
  console.log("execing " + cmd);
  try {
    const [isLive, parsed] = parseCmd(cmd);
    cmd = parsed;
    const [result, setResult] = createSignal(db.exec(cmd));
    // also do our subscribing if the cmd is a select.
    // `result` would need to be a signal updatable by notifier.

    // is a for component usable for nested arrays?
    return (
      <Show when={result()[0] != null} fallback={<div>[]</div>}>
        <table>
          <thead>
            <tr>
              {result()[0].columns.map((c) => (
                <th>{c}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {result()[0].values.map((v) => (
              <tr>
                {v.map((c) => (
                  <td>{c}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </Show>
    );
  } catch (e) {
    return <div>{e.message}</div>;
  }
}

function Input() {
  const [cmd, setCmd] = createSignal("");
  function processCommand(e) {
    e.preventDefault();
    setCommands((prev) => [cmd(), ...prev]);
    setCmd("");
    return false;
  }

  return (
    <div class="input">
      <span class="prompt">{prompt}</span>
      <form onSubmit={processCommand}>
        <input
          type="text"
          onChange={(e) => setCmd((e.target as any).value)}
          value={cmd()}
          autofocus
        ></input>
      </form>
    </div>
  );
}

// Prevent people from bricking themselves. If they do, whatever. The DB is ephemeral.
function assertAllowed(cmd: string) {
  if (cmd.split(";").length > 1) {
    throw new Error("Multiple queries per line are not allowed.");
  }

  cmd = cmd.trim().toLowerCase();
  const allowed =
    cmd.startsWith("insert") ||
    cmd.startsWith("update") ||
    cmd.startsWith("select") ||
    cmd.startsWith("delete") ||
    cmd.startsWith("live");

  if (!allowed) {
    throw new Error(
      "Only select / insert / update / delete queries may be run."
    );
  }
}

function isSelect(cmd: string) {
  return cmd.trim().toLowerCase().startsWith("select");
}

function parseCmd(cmd: string): [boolean, string] {
  const normalized = cmd.trim().toLowerCase();
  if (normalized.startsWith("live")) {
    const baseCmd = cmd.substring("live".length).trim();
    if (!baseCmd.toLowerCase().startsWith("select")) {
      throw new Error("live queries can only be select queries");
    }
    assertAllowed(baseCmd);
    return [true, baseCmd];
  }

  assertAllowed(cmd);
  return [false, cmd];
}