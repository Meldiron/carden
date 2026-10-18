# Custom product pages

Extra versions of Carden's App Store page, each with its own screenshots, promotional text, URL and
(optionally) a deep link and search keywords. Built for audiences and campaigns: Apple Ads, links in
posts and newsletters, the homepage, and searches for a theme. Eight pages are set up as **drafts** on
App Store Connect (2026-10-16). Nothing has been submitted for review.

Tool: `tools/store/custom_pages.py`. Page definitions: `store/metadata/custom_pages/<slug>.json`.
Slides: `store/custom/<slug>/01.png ...`. Apple ids and URLs: `store/metadata/custom_pages/apple.json`.

## What Apple offers (research, October 2026)

- **What a page can change.** Screenshots, app previews and promotional text, per locale. Since 2025 it can
  also have a deep link and search keywords. The name, subtitle, icon, description and keyword field come from
  the default page. Since 5 October 2026 a page can also carry a product page header and a search-result
  asset; these show on iOS 27 and later [1][7][8].
- **Limits.** 70 pages per app (up from 35 on 29 October 2025). Each display size takes 10 screenshots and
  3 previews. Promotional text is 170 characters. Pages show on iOS 15 and later [1][2][3][6].
- **Review.** Every page version is reviewed and shows only once it is approved. Once the app itself is
  approved, a page can be submitted on its own, without an app version; it is reviewed against the latest
  version. Before the app's first approval, a page can only go in the same submission as that first version.
  Drafts can be made before release: these eight were created while 2.0.0 was still in Prepare for Submission
  [2][10]. To change an approved page, create a new version, edit it and submit it; the URL stays the same.
  Promotional text can be changed at any time [2][5].
- **Keywords (search).** A page can take over keywords from the app's latest *approved* keyword field. People
  who search one of them then see that page in the results instead of the default page. Each keyword
  should belong to one page only. Keyword-only changes go live without review, but keywords cannot be changed
  while the page is in review. Until Carden's first approval the app has no approved keywords, so the tool
  only records which keywords each page should take [1][2][4].
- **Deep link.** Each page version can have a deep link: a universal link (Apple's advice) or a custom URL,
  with no shorteners or redirects. It is reviewed with the page and works on iOS 18 and later. It changes
  only where the App Store's **Open** button goes. That includes the first open right after an install, but
  it is not deferred deep linking. Our links are `https://play.carden.page/...` universal links. They open
  the app from 2.0.0 on, and a page goes live only after 2.0.0, so every player who sees a page has a build
  that handles them [2][11].
- **URL.** Each page has its own URL: the App Store link plus `?ppid=<page id>`. Apple's `url` attribute
  still carries the app's first name in the path (`/us/app/card-jigsaw-world/...`). The short form
  `https://apps.apple.com/app/id6821644423?ppid=<id>` opens the same page; share that one. A page that is
  turned off (`visible` false) or deleted sends its URL to the default page [2].
- **Apple Ads.** Pages and their deep links can be used on the Today tab, the Search tab and in search
  results. Ad variations (one ad group, several pages) are for search results only [12].
- **Analytics.** App Analytics > Acquisition > Product Pages shows impressions, downloads, conversion rate
  and proceeds for each page. A page needs at least 5 first-time downloads before data shows. Apple gives no
  data per keyword [2][13].
- **What it is worth.** Apple reports an average gain of 2.5 percentage points in conversion, 156% over a
  1.6% baseline. Case studies run from +20% to +137%. These numbers come from Apple and vendors; treat them
  as optimistic [1][16].
- **What other games do.** Most games make audience and intent pages: Art Puzzle has pages for anti-stress
  and cozy players, Trivia Crack has separate pages for older and younger players. Others make genre or
  feature pages, seasonal pages (Valentine's Day, holidays, Black Friday), competitor-keyword pages, and one
  page per ad channel or influencer. About 40% of the top 50 games use custom pages in Apple Ads. Card and
  word games use the most, and games made the most pages of any category in 2025 [9][14][15].

## The pages

The first three slides carry each page: they are what search results and ads show. The pages reuse
the default set's look (`tools/store/compose_glass.py`): glass panes, one phone size, SF Pro Rounded
headlines, light app on light slides and the dark finale. Every slide shows the real app, with no VIP talk and no AI
pictures (the owner's rules for the default set, `.claude/skills/store-screenshots/SKILL.md`). Slides 4 to 6
reuse slides of the default set by their key in `slides()` (`{"default": "daily"}`), so a new slide in the default
set does not shift them.

| Page (slug) | Audience | Slides 1-3 | Deep link | Keywords to take over |
| --- | --- | --- | --- | --- |
| Calm and cozy (`calm`) | Relaxing, cozy, zen players | A calm puzzle for quiet moments / Help when you want it / Bring the colour back | none (Home) | relax, cozy, zen |
| Art and museum paintings (`art`) | Art lovers, museum visitors | Museum paintings, card by card / Monet, Van Gogh, Hiroshige and more / A new picture every day | `/library/pack/pack-impressionists` (a free starter pack) | art, museum, painting |
| Nature and animals (`nature`) | Wildlife, nature, photography | Wildlife and wild places / Swap cards. Reveal the picture. / Quiet places around the world | `/library/pack/pack-butterflies` (free, the pack on slide 1) | nature |
| Giant puzzles (`giant`) | Experienced jigsaw players | Giant boards of hundreds of cards / Pinch to zoom, follow the map / One picture, four ways | `/library?filter=giant` | large (added to the keyword field in 2.0.0) |
| Daily puzzle (`daily`) | Daily-ritual players, re-engagement | A new picture every day / Keep your streak going / Every month back to 2023 | `/daily` | daily |
| Your own photos (`photos`) | Photo, pet and family puzzles; gift season | Puzzle your own photos / Only you can see your photos / One picture, four ways | `/my-puzzles` | family |
| Four shapes (`shapes`) | Hexagon, mosaic, tile puzzle fans | One picture, four ways to cut it / Six sides to join on / Bring the colour back | none (shapes open by level) | tiles, swap |
| Winter holidays (`winter`) | Seasonal: 1 December to early January | Winter in pictures / Swap cards. Reveal the picture. / Quests and world-day events | `/events` | none (seasonal, for ads and links) |

Each JSON also holds the promotional text (all under 170 characters), the audience, the story, search terms
for Apple Ads (`adSearchTerms`, which are not assigned to the page) and a note for every new slide.

## Commands

```sh
.venv/bin/python tools/store/custom_pages.py compose [SLUG ...]   # render slides into store/custom/<slug>/ (about 40 s a page)
.venv/bin/python tools/store/custom_pages.py compose --contrast   # measure every headline only (4.5:1 minimum)
.venv/bin/python tools/store/custom_pages.py plan [SLUG ...]      # read Apple, print what sync would change
.venv/bin/python tools/store/custom_pages.py sync [SLUG ...]      # create or update the drafts
.venv/bin/python tools/store/custom_pages.py list [SLUG ...]      # ids, states, deep links, screenshot counts, URLs
```

`sync` matches a page by the id in `apple.json`, then by its reference name. It creates the page with
version 1 and the app's primary locale (en-GB), and it sets the deep link and promotional text. It uploads
the 6.9-inch set (`APP_IPHONE_67`, the same display type as the default page): files that changed are
replaced, files that are gone are removed, and the order follows the file names. Keywords are assigned once
the app has approved keywords. `sync` never submits anything and never touches the default page. A version
that is waiting for review or in review is left alone. On an approved page, `sync` changes nothing unless
you pass `--new-version`, which starts a new draft version. A later sync of an approved page without
`--new-version` does not update its promotional text either; change that in App Store Connect or start a new
version.

Composing reads the light captures in `store/raw/` (git-ignored; made by the store screenshot test, see the
store-screenshots skill) and pack covers from our Storage. A new slide's crop boxes are in `BOXES` in
`custom_pages.py`. After new captures, check them on a coordinate grid, as the skill describes for the
default set.

Screenshots go through Apple's `appScreenshotSets` endpoints, the same route `asc_publish.py screenshots`
uses. API 4.5.1 (October 2026) deprecates these in favour of the App Asset Library (`appAssetLibraryImages`
and `appAssetLibraryPlacements` with placement group `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`). Both routes
work today. Move both tools together when Apple turns the old one off [6].

## Submitting later (by hand, when the owner decides)

1. Wait for the first App Store approval of 2.0.0. Putting pages in the first submission is possible, but
   it adds items to the first review for no gain: before launch, the pages have nobody to reach.
2. Then run `custom_pages.py sync` again. It assigns the keywords that the approved keyword field now holds.
   Check with `list`.
3. Submit a few pages first: Calm and cozy, Daily puzzle and Your own photos (broad audiences), then Art,
   Nature and Giant. To submit, open App Store Connect > Carden > Custom Product Pages > the page >
   Add for Review > Submit to App Review, or add `appCustomProductPageVersion` items to a `reviewSubmission`
   through the API. Pages can go in one submission. Keep them out of a submission that also carries an app
   version, unless that version needs them.
4. Winter holidays: submit by mid-November so it is live on 1 December. Refresh its first slide before
   then, when the season's event packs and captures are final. Turn it off (`visible` false) in January
   and turn it on again the next winter, after a new version with that year's packs.
5. After approval, a page's screenshots and deep link change only through a new version
   (`sync --new-version`, then submit). Promotional text and keywords can change without review.

## Using the pages

- **Apple Ads.** One ad group per page: Calm on relaxing and cozy terms, Art on art and painter terms, Giant
  on big or hard jigsaw terms, Photos on photo-puzzle terms, Winter in December. Search ad variations can
  test pages against each other. The search terms are in each JSON (`adSearchTerms`).
- **Links.** Use the short URL from `apple.json` (`shortUrl`) in posts, newsletters and the homepage (for
  example the Art page from a museum or art post, Photos from a gift post). Keep the plain App Store link
  for everything general.
- **Measuring.** App Analytics > Acquisition > Product Pages, after at least 5 first-time downloads per page.
  Keep a page that converts better than the default page for its audience, and change or retire one that
  does not.
- The game itself shows no custom pages: it has no in-app App Store sheets, and it talks only to Appwrite and Apple.

## Header and search-result art (iOS 27)

Since 5 October 2026 a product page carries two creative assets: a **header** at the top of the page, and a
**search-result** image that replaces the screenshot row in search results. Both show on iOS 27 and iPadOS 27
and later. The default page, every custom page and every product page optimization treatment can each have
one header and one search asset per localization. Pages without a search asset keep showing their
screenshots [17][18][19].

**Specs** (App Store Connect API reference data, `GET /v1/appAssetLibraryRefData`, and Apple's help [17]):

| Slot | Image | Video |
| --- | --- | --- |
| Header | 5244 x 2950 PNG (16:9, "universal": it can also fill the search slot), **or** 3840 x 1646 PNG (21:9, header only). One header per page | 3840 x 1646, 30 or 60 fps, 5-30 s, .mov/.m4v/.mp4, loops, starts muted |
| Search result | 3:2 from 1920 x 1280 to 3840 x 2560, JPEG or PNG, or the 5244 x 2950 universal PNG | 3:2, same sizes, 5-30 s, always muted |

There is no alpha channel, the limit is 500 MB, and one file serves every device (placement group
`DEFAULT_PROFILE`).

**Safe areas.** These come from the "Art Safe Area" layer of Apple's templates. Only this part shows on
every device; the rest can be cropped.

| File | Safe area (x0, y0, x1, y1) |
| --- | --- |
| 5244 x 2950 | 1921, 660, 3323, 1622 (1402 x 962, centred, above the middle) |
| 3840 x 1646 | 1097, 493, 2743, 1154 (1646 x 661, centred) |
| 3840 x 2560 | 836, 765, 3004, 1795 (2168 x 1030, centred) |

**How Apple shows them.** On an iPhone, the header runs edge to edge at the very top of the page, behind the
status bar, with the glass Back and Share buttons over its top corners. The icon, name, subtitle and Get
button sit below it on the page, not on the art. The search result is a full-width card with rounded
corners, about 3:2 and about 365 pt wide, below the app's row. A useful check is to shrink it to 384 px and
see if the text still reads [19].

**Apple's advice.**
- Header: one clear idea, set the tone, keep the focal point centred.
- Search result: "state the obvious" and show the real interface.
- Text is allowed but optional. Use a short phrase that enhances the visual, localized.
- Never include prices, URLs, copyright symbols, other platforms, awards or Apple recognitions, and keep
  everything suitable for 4+.

In the first weeks, most adopters used brand key art for the header, and real UI with a short line for the
search asset [19][20].

**Our art** (`tools/store/header_assets.py`, definitions in `store/metadata/custom_pages/header_assets.json`,
files in `store/custom/header/<page>/`, git-ignored):
- **Header.** The lotus mark and one short line ("Your calm picture puzzle", or the custom page's own
  line) sit in the safe area, on white. Real pack pictures fan out as cards on both sides, real board
  groups are lifted out of captures, and the slides' glass panes sit behind. The 21:9 file renders the
  same scene for its own safe area.
- **Search result.** The page's first headline ("Swap cards. Reveal the picture." on the default page)
  sits on the left of the safe area. The real app is on the right, in the slides' phone frame, with a
  lifted card and two pictures behind.
- **Checks.** Every line is measured against what is behind it (all 16:1 or better). `preview` writes the
  safe area over each file, and writes the files at iPhone and iPad size and at 384 px.

Commands:

```sh
.venv/bin/python tools/store/header_assets.py compose [PAGE ...]   # PAGE: default or a custom page slug
.venv/bin/python tools/store/header_assets.py preview [PAGE ...]
.venv/bin/python tools/store/header_assets.py list [PAGE ...]      # what is placed on Apple
.venv/bin/python tools/store/header_assets.py plan [PAGE ...]      # what upload would send
.venv/bin/python tools/store/header_assets.py upload [PAGE ...] --yes [--header 16x9|21x9]
```

`upload` goes through the App Asset Library in five steps:
1. `POST /v1/appAssetLibraryImages` (category `CREATIVE_ASSETS`, linked to the app's asset library).
2. Upload the file to the presigned URLs.
3. `PATCH uploaded: true`.
4. Wait until Apple has checked the file.
5. `POST /v1/appAssetLibraryPlacements` (`PRODUCT_PAGE_HEADER_ASSET` or `APP_STORE_SEARCH_RESULTS_ASSET`,
   group `DEFAULT_PROFILE`) on the page's en-GB localization.

The default page uses the editable App Store version (2.0.0). A custom page uses its draft version. A
changed file replaces its placement; an unchanged one is kept. The header placed is the 16:9 universal
file unless you pass `--header 21x9`. `upload` submits nothing. Each image's reference name ends in a short hash
of its file (the library refuses a name it already holds), and a new file is uploaded before the old placement goes,
so a refused file never leaves a page without art. Art on the default page is locked while 2.0.0 sits in a review
draft: take the version item out of the draft, upload, then `asc_publish.py draft --events` puts it back.

Review: the art is reviewed with the version or page it is placed on. Before the app's first approval it
can only go with that first version. After that it can also be submitted on its own from the Asset
Library [18].

## Sources

1. https://developer.apple.com/app-store/custom-product-pages/
2. https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions/
3. https://developer.apple.com/news/?id=gf6mgrs6 (70 pages, 29 October 2025)
4. https://developer.apple.com/videos/play/wwdc2025/328/ (keywords for custom product pages)
5. App Store Connect API: appCustomProductPages, appCustomProductPageVersions (`deepLink`),
   appCustomProductPageLocalizations (`promotionalText`, `searchKeywords`); https://developer.apple.com/documentation/appstoreconnectapi
6. https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces (App Asset Library)
7. https://developer.apple.com/videos/play/wwdc2026/205/
8. https://adapty.io/blog/app-store-asset-library/
9. https://adapty.io/blog/custom-product-pages-app-store/
10. https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-a-custom-product-page
11. https://developer.apple.com/forums/thread/757367 (the deep link sets the Open button)
12. https://ads.apple.com/app-store/help/ad-placements/0081-ad-placement-options and https://ads.apple.com/app-store/help/ads/0077-create-ad-variations
13. https://developer.apple.com/help/app-store-connect-analytics/acquisition/custom-product-pages
14. https://www.apptweak.com/en/aso-blog/how-mobile-games-use-custom-product-pages-for-apple-search-ads
15. https://www.mobileaction.co/report/2026-aso-report/custom-product-pages/
16. https://splitmetrics.com/custom-product-pages-from-ideas-to-results/
17. https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
18. https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets and
    https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-assets-from-asset-library
19. https://developer.apple.com/app-store/asset-best-practices/ (templates: creative_assets-universal_asset_template,
    -product_page_header_template and -search_results_template on devimages-cdn.apple.com)
20. https://objectgraph.com/blog/ios-27-app-store-header-and-search-results-art/ and https://neoads.substack.com/p/app-store-creative-assets
