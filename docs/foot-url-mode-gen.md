# URL Mode Foot

I'm trying to replicate the URL hinting logic from foot into ghostty.

Here is how they selected for the url key labels.

● The key logic is in generate_key_combos() at url-mode.c:562. Here's how it works:

  1. Alphabet source: It reads conf->url.label_letters — a configurable string of
  characters (e.g. "sadfjklewcmpgh").
  2. Generating combos: It builds hint labels iteratively, similar to how you'd count in
  a custom base:
    - Start with an empty prefix ""
    - For each prefix, append every letter from the alphabet to produce new hints (e.g.
  s, a, d, f, ...`)
    - If that's not enough hints for the number of URLs, it takes the earliest hints as
  new prefixes and extends them (e.g. ss, sa, sd, ...`), producing multi-character labels
    - This continues until there are enough combos for all URLs
  3. Reversal: The hints are built in reverse order (new char prepended), then reversed
  at the end (line 604-611), so the first character typed narrows the most.
  4. Assignment (urls_assign_key_combos, line 614): Combos are assigned to URLs in
  reverse order (tll_rforeach), so URLs appearing later on screen get earlier/shorter
  labels. Duplicate URLs (same string) reuse the same key combo rather than consuming a
  new one.


● Here's generate_key_combos() from url-mode.c:562-612:
```c
  static void
  generate_key_combos(const struct config *conf,
                      size_t count, char32_t *combos[static count])
  {
      const char32_t *alphabet = conf->url.label_letters;
      const size_t alphabet_len = c32len(alphabet);

      size_t hints_count = 1;
      char32_t **hints = xmalloc(hints_count * sizeof(hints[0]));

      hints[0] = xc32dup(U"");

      size_t offset = 0;
      do {
          const char32_t *prefix = hints[offset++];
          const size_t prefix_len = c32len(prefix);

          hints = xrealloc(hints, (hints_count + alphabet_len) * sizeof(hints[0]));

          const char32_t *wc = &alphabet[0];
          for (size_t i = 0; i < alphabet_len; i++, wc++) {
              char32_t *hint = xmalloc((prefix_len + 1 + 1) * sizeof(char32_t));
              hints[hints_count + i] = hint;

              /* Will be reversed later */
              hint[0] = *wc;
              c32cpy(&hint[1], prefix);
          }
          hints_count += alphabet_len;
      } while (hints_count - offset < count);

      xassert(hints_count - offset >= count);

      /* Copy slice of 'hints' array to the caller provided array */
      for (size_t i = 0; i < hints_count; i++) {
          if (i >= offset && i < offset + count)
              combos[i - offset] = hints[i];
          else
              free(hints[i]);
      }
      free(hints);

      /* Reverse all strings */
      for (size_t i = 0; i < count; i++) {
          const size_t len = c32len(combos[i]);
          for (size_t j = 0; j < len / 2; j++) {
              char32_t tmp = combos[i][j];
              combos[i][j] = combos[i][len - j - 1];
              combos[i][len - j - 1] = tmp;
          }
      }
  }

  And the assignment in urls_assign_key_combos() at url-mode.c:614-682:

  void
  urls_assign_key_combos(const struct config *conf, url_list_t *urls)
  {
      const size_t count = tll_length(*urls);
      if (count == 0)
          return;

      char32_t *combos[count];
      generate_key_combos(conf, count, combos);

      size_t combo_idx = 0;

      tll_rforeach(*urls, it) {
          /* Skip if same ID+URL already processed */
          bool id_already_seen = false;
          tll_rforeach(*urls, it2) {
              if (&it->item == &it2->item)
                  break;
              if (it->item.id == it2->item.id &&
                  streq(it->item.url, it2->item.url))
              {
                  id_already_seen = true;
                  break;
              }
          }
          if (id_already_seen)
              continue;

          /* Reuse key combo for duplicate URLs */
          bool url_already_seen = false;
          tll_rforeach(*urls, it2) {
              if (&it->item == &it2->item)
                  break;
              if (streq(it->item.url, it2->item.url)) {
                  it->item.key = xc32dup(it2->item.key);
                  url_already_seen = true;
                  break;
              }
          }

          if (!url_already_seen)
              it->item.key = combos[combo_idx++];
      }

      /* Free combos we didn't use up */
      for (size_t i = combo_idx; i < count; i++)
          free(combos[i]);
  }
```
