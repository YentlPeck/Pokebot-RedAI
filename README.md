# Written by Yentl

I tried to see if I could create a pokemon red speedrunning bot. Overall the results were decent. I was able to copy a bot from 10 years ago and optimize it. I had hoped to get below the human world record time but that was a lot of min maxing which I did not consider usefull anymore. This was my first project using Claude code and Codex together. The claude models are good at coding while the openAI models help with the review and planning. Together they are creating excellent results. 

# Written by Claude
# PokeBot Red

A Lua bot that speedruns Pokemon Red through PyBoy from a fresh boot using normal buttons and read-only game observations. This is the final v94 PB code, with portable Python paths.

Best verified run: **1:46:35.71 official**, seed **1870021768** (26 October 2026). Bot clock: 1:46:26.67; in-game time: 1:44:15.42. A single arbitrary seed can reset early; this bot pursues fast runs.

Use Python **3.12** (tested with 3.12.1 on Windows x64):

```sh
python -m pip install -r requirements.txt
```

Supply your own legally obtained, unmodified English Pokemon Red (USA/Europe) ROM outside this folder. Expected SHA-1: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`. No ROM, save, state, or run data is distributed.

One game with the final settings:

```sh
python run.py --rom "/path/to/your/red.gb" --seed 12345
```

Replay the PB and verify its button-log SHA-256:

```sh
python run.py --rom "/path/to/your/red.gb" --replay-pb
```

Runs are headless. Output goes to `~/pokebot-runs/refstrat-v94/`; use `--output-dir` to choose another location outside this repository. Every run starts with empty cartridge RAM in memory; normal in-game saves survive only the run's power cycles. Lua 5.1 comes from Lupa. Numeric move/item IDs in diagnostics avoid a disassembly dependency. Exact flags and expected hash: [docs/pb.json](docs/pb.json). Results and changes: [docs/RESULTS.md](docs/RESULTS.md).

Original PokeBot: Kyle Coburn and Michael Jondahl; Rhys Jones maintained the inherited fork. Final routing and Python adaptation: Yentl's 2026 project, with AI assistance. MIT license; original copyright retained in [LICENSE](LICENSE). Sources, third-party notices, and verification date: [NOTICE.md](NOTICE.md).
