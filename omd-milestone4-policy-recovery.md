# Milestone 4 - Math Policy + Recovery UX

## 1) Math Rendering Policy Menu

Use `View -> Math Rendering` and switch between these options:

- Styled Text (Safe)
- Disabled (Literal $...$)
- External Tools (LaTeX)

Inline sample: $E = mc^2$

Display sample:

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

Expected:
- `Styled Text (Safe)`: math appears styled (no external tool execution).
- `Disabled`: literal markdown math syntax remains visible (`$...$`, `$$...$$`).
- `External Tools (LaTeX)`: may render higher-fidelity output if toolchain is available.

## 2) Remote Image Toggle

Use `View -> Math Rendering -> Allow Remote Images` to toggle.

![Remote Markdown Icon](https://raw.githubusercontent.com/github/explore/main/topics/markdown/markdown.png)

Expected:
- Toggle OFF: remote image should not load (fallback text may appear).
- Toggle ON: remote image may load if network and decoder are available.

## 3) Preference Persistence

After choosing a math policy and remote-image setting:
- Close and relaunch app on this file.
- Confirm menu checkmarks persist.
