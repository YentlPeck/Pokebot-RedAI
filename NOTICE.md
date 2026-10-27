# Credits and licensing

This repository uses the MIT license, as requested for the final project copy. The original notice is retained verbatim in LICENSE and candidates/refstrat-v94/engine/LICENSE:

Copyright (c) 2014 Kyle Coburn and Michael Jondahl

Kyle Coburn created the original concept and Red/Yellow routing; Michael Jondahl developed combat and integrations. Rhys Jones maintained the inherited BizHawk fork. Sources checked online on **2026-10-27**:

- Original PokeBot lineage: https://github.com/CryZe/PokeBot ; MIT license: https://github.com/CryZe/PokeBot/blob/master/LICENSE
- Inherited PokeBot v2.4.8 fork: https://github.com/jonese1234/PokeBotBad ; credits: https://github.com/jonese1234/PokeBotBad/blob/master/Readme.md
- Version-pinned license: https://github.com/jonese1234/PokeBotBad/blob/2e882849cac6e9b6a6ce62dcd689c64160d1d51e/LICENSE
- Local provenance and engine fixes: candidates/refstrat-v94/engine/ENGINE_CHANGES.md. The source adapter identifies upstream commit 2e882849cac6e9b6a6ce62dcd689c64160d1d51e.

The original kylecoburn/PokeBot URL no longer resolved during this check; the preserved lineage and fork above retain the same MIT notice and authors.

engine/external/json.lua is JSON4Lua 1.0.0 by Craig Mason-Jones, declares MIT in its retained header, and points to https://github.com/craigmj/json4lua/ . Its separate upstream notice is retained alongside the module in external/LICENCE.txt, retrieved from https://github.com/craigmj/json4lua/blob/1.0.0/doc/LICENCE.txt on 2026-10-27. The rockspec says GPL, while the shipped module header and version-tagged license file explicitly say MIT; this export retains the latter notices for this module.

The pret Pokemon Red/Blue disassembly (https://github.com/pret/pokered) was consulted by the source project. No standalone redistribution license was found in its root listing or local copy on 2026-10-27. No pret files are included or required here; its two diagnostic label tables were replaced with numeric IDs. Pokemon game assets and trademarks are not covered by this project's MIT license.

The final route, overlays, and Python integration are from Yentl's 2026 project. This export changes paths/configuration and diagnostic labels only; all shipped Lua files match their source bytes. See docs/SOURCE_SHA256.json.
