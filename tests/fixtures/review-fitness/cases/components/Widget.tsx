// characterization corpus: check 2 (a11y) and check 3 (empty catch) in one file
export function Widget() {
  return (
    <div>
      <img src="/logo.png" />
      <img src="/hero.png" alt="hero" />
      <img>
      <imgx src="/nope.png" />
      <input type="text" class="q" />
      <input type="hidden" name="csrf" />
      <input type=hidden name="csrf2" />
      <input id="email" type="email" />
      <input aria-label="Search" type="search" />
      <input aria-labelledby="lbl" type="text" />
      <input data-id="x" type="text" />
      <input type="submit" />
      <input>
      <INPUT CLASS="Y" />
      <img
        src="/multiline.png"
      />
    </div>
  )
}
export function both() {
  try { risky() } catch (e) {}
  return <img src="/inline.png" />
}
