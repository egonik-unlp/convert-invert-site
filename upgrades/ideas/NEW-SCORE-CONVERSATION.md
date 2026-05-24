To use as a judge score for possible tracks I want to use mutual information. I'm not sure whether to use MI, RMI or NMI

Your idea is in the right family, but plain mutual information is probably not the best final score for this task unless you define the random variables very carefully. For matching Spotify metadata to Soulseek filenames, normalization and background correction matter a lot.

Pensado durante 19s

For your use case, I would not use raw MI as the final judge score. I would use NMI or an adjusted/reduced MI-like score, depending on how much data you have.

My practical recommendation:

If you only compare one Spotify track against one candidate filename:
use NMI-like normalization, or better: weighted token/field similarity.

If you have a corpus of past searches, accepted matches, rejected matches:
use PMI / normalized PMI features, possibly with reduced/adjusted MI correction.

If you want one simple 0–1 judge score:
use NMI-style scoring, not raw MI.
Why plain MI is probably dangerous here

Mutual information answers:

How much does knowing variable X reduce uncertainty about variable Y?

That is great when you have random variables and a probability distribution.

But in your case you usually have something like:

Spotify:
Track: Looking at Your Pager
Artist: KH
Album: Looking at Your Pager

Soulseek candidate:
KH - Looking at Your Pager.flac

That is not automatically a pair of random variables. It is a pair of strings / metadata records. To use MI, you need to decide what X and Y are.

Possible choices:

X = tokens in Spotify metadata
Y = tokens in filename

But then raw MI tends to be biased by:

longer filenames
more tokens
repeated tokens
generic words: edit, remix, radio, version, original, feat
rare weird tokens
different token vocab sizes

So raw MI may say “there is a lot of shared information” simply because the filename is long and noisy.

That is the key problem: raw MI is not naturally comparable between candidates of different length and entropy.

NMI is the safer default

Normalized mutual information tries to answer:

How much of the available information overlaps, relative to how much information both sides contain?

Typical forms are:

NMI = I(X;Y) / sqrt(H(X) H(Y))

or

NMI = 2 I(X;Y) / (H(X) + H(Y))

The advantage is that the score is usually bounded, often interpretable as something like 0 to 1.

For a judge score, this is convenient because your current mental model probably wants:

0.0 = terrible match
1.0 = excellent match

So if you want an MI-family score directly usable as a threshold, NMI is closer to what you want than MI.

What about RMI?

Here I need to be careful: RMI is not as universally standardized as MI or NMI. Depending on the source, people may mean things like:

Reduced Mutual Information
Relative Mutual Information
Regional Mutual Information
Rank Mutual Information

For your task, the useful interpretation would be something like reduced / adjusted mutual information:

RMI ≈ observed MI - expected MI by chance

or a normalized version of that.

This is attractive because candidate filenames share many common music words by accident:

remix
edit
radio
version
original
feat
club
mix
extended

Raw MI or even NMI may overvalue those. A reduced/adjusted MI score can say:

Yes, these tokens overlap, but this overlap is not surprising, so it should not count much.

That is conceptually very good for your problem.

But the cost is that RMI needs a background model:

How common is this token in all candidate filenames?
How common is this artist token?
How often do these tokens co-occur by chance?
What does a random bad candidate look like?

Without that corpus, RMI becomes hard to estimate robustly.

My recommendation

Use this hierarchy:

Simple version

Use NMI, but separately for fields:

score =
0.50 \* NMI(track_title, filename)

- 0.35 \* NMI(artist, filename)
- 0.10 \* NMI(album, filename)
- 0.05 \* file_quality_score

- penalties

Penalties should include:

wrong artist
live version when original requested
radio edit vs extended mix mismatch
instrumental/acapella mismatch
remix mismatch
cover version
low bitrate / non-audio / suspicious extension

This will probably work better than one global MI over all text.

Better version

Use NPMI / PMI with IDF weighting.

For each important token pair or token overlap:

PMI(token_spotify, token_filename)
= log p(token_spotify, token_filename) / (p(token_spotify) p(token_filename))

Then normalize:

NPMI = PMI / -log p(token_spotify, token_filename)

This makes rare meaningful overlaps valuable, but prevents raw MI from exploding.

Example:

"KH" + "Looking" + "Pager"

should count more than:

"Original" + "Mix" + "Edit"

because the latter are common in music filenames.

Best version if you have data

Train/calibrate the score using accepted/rejected matches:

features:
title_nmi
artist_nmi
album_nmi
filename_length_penalty
remix_mismatch
live_mismatch
extension
bitrate / size if available
token_idf_overlap
npmi_overlap

model:
logistic regression or small gradient boosted model

Then the output is directly:

P(candidate is correct match)

That would be more useful than forcing MI itself to be the judge.

Bottom line

For your current project, I would say:

Do not use raw MI.
Use NMI if you want a simple normalized judge score.
Use reduced/adjusted MI only if you have enough background corpus statistics.
Use NPMI + field weighting if you want the MI idea but adapted to string matching.

So the practical answer is:

Default: NMI
Better: field-weighted NPMI / IDF-weighted overlap
Best: calibrated classifier using NMI/NPMI as features

Your idea is close, but the important correction is: MI is a dependence measure over distributions, not automatically a pairwise string similarity score. For track matching, the normalization/correction is not a detail; it is what makes the score usable.

what about relative mutual information

“Relative mutual information” is a bit ambiguous, so I’m going to separate the useful definition for your track-matching problem from the naming ambiguity.

Pensado durante 7s

Relative mutual information is probably the most useful MI-family idea for your track judge, but only if you treat it as directional information coverage.

The common meaning is close to the uncertainty coefficient:

U(Y | X) = I(X;Y) / H(Y)

Meaning:

What fraction of the uncertainty in Y is explained by knowing X?

This is a normalized MI score in [0, 1], and it is directional, unlike ordinary MI. U(Y|X) and U(X|Y) can be different.

For your case, that asymmetry is actually useful.

How I would map it to track matching

Let:

S = Spotify metadata
F = Soulseek filename / candidate metadata

Then you can compute two relative scores:

coverage = I(S;F) / H(S)

Meaning:

How much of the Spotify track identity is explained by the candidate filename?

This is the important one. If the Spotify title + artist information is almost fully present in the filename, this should be high.

Then:

purity = I(S;F) / H(F)

Meaning:

How much of the filename information is actually relevant to the Spotify track?

This punishes noisy filenames.

Example:

Spotify:
Artist: KH
Track: Looking at Your Pager

Candidate A:
KH - Looking at Your Pager.flac

Candidate B:
VA - Best Ibiza Techno Club Remix Extended Pack 2022 - Looking at Your Pager.flac

Both may contain the track title, but Candidate B has much more extra entropy/noise. So:

coverage may be high for both
purity should be lower for B

That is exactly what you want.

Relative MI vs NMI

NMI gives you a symmetric score:

NMI = I(S;F) / sqrt(H(S)H(F))

or:

NMI = 2I(S;F) / (H(S) + H(F))

That is nice when the two objects have equal status.

But in your case they do not have equal status:

Spotify metadata = target identity
Soulseek filename = noisy observation

So I think relative MI is conceptually better than symmetric NMI.

The asymmetry lets you distinguish:

Does the filename contain the Spotify identity?

from:

Is the filename mostly about that Spotify identity?

Both matter, but they are not the same question.

Practical judge score

I would use something like:

score =
0.65 \* coverage

- 0.25 \* purity
- 0.10 \* quality_score

- penalties

Where:

coverage = I(S;F) / H(S)
purity = I(S;F) / H(F)

In plain words:

coverage: "Did we recover the target track?"
purity: "Is the candidate mostly this track, or is it noisy/misleading?"

For track matching, I would weight coverage more than purity, because filenames often contain harmless extras:

.flac
320kbps
WEB
CDM
2020
Soulseek folder names
label names

You do not want to reject a correct file just because it has extra metadata.

But I would not compute it over raw tokens naively

This is the important caveat.

If you compute entropy over raw tokens, generic music words will pollute the score:

original
mix
edit
remix
feat
version
radio
club
extended

So I would use weighted tokens:

artist tokens: high weight
title tokens: high weight
album tokens: medium/low weight
generic release tokens: low or negative weight
format tokens: almost zero

In practice, your “relative MI” may become more like:

weighted shared information / weighted Spotify information

That is not pure textbook MI, but it is probably better engineering.

My recommendation

For your judge:

Use relative MI ideas, not raw MI.

More specifically:

primary_score = I(Spotify; Filename) / H(Spotify)
secondary_score = I(Spotify; Filename) / H(Filename)

Then combine them.

I would prefer this over plain NMI because the task is asymmetric: the Spotify track is the reference, and the Soulseek filename is a noisy candidate.

A good practical formulation would be:

track_identity_score =
0.70 \* relative_info_about_spotify

- 0.20 \* relative_info_about_filename
- 0.10 \* file_quality

- mismatch_penalties

So my ranking for your use case would now be:

Best conceptual fit: Relative MI / uncertainty coefficient style
Good simple fallback: NMI
Bad final judge score: raw MI
Best production version: relative MI-like features + calibrated classifier
