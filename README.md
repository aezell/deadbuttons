# Deadbuttons

A link checker for [88x31 buttons](https://en.wikipedia.org/wiki/Web_banner#Standard_sizes) — those tiny badge images used as blogroll links, webring buttons, and friend badges across the IndieWeb and SmallWeb.

Over time, the sites behind those buttons disappear. Deadbuttons finds them and tells you which links are still alive.

## Try it

A live instance is running at **https://checker1994-bj4r6.sprites.app/**

1. Paste the URL of a page that has 88x31 button links
2. Hit **Scan for dead buttons**
3. Watch results appear in real time as each button is found and its link is checked

Each result shows the button image, where it links, and whether that link is alive, dead, redirecting, or erroring out.

## Run it yourself

You'll need Elixir 1.15+ and Erlang/OTP 26+.

```
git clone https://github.com/aezell/deadbuttons.git
cd deadbuttons
mix setup
mix phx.server
```

Then visit [localhost:4000](http://localhost:4000).

## What counts as a "button"

Deadbuttons looks for `<img>` tags inside `<a>` links where the image is exactly 88x31 pixels. It checks dimensions two ways:

- HTML `width` and `height` attributes on the `<img>` tag
- Actual pixel dimensions from the image file (GIF, PNG, or JPEG)

## Privacy

No accounts, no database, no cookies, no tracking. Enter a URL, get results, done. Nothing is stored.
