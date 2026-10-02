pragma Singleton
import QtQuick

QtObject {
    id: root

    // ─────────────────────────────────────────────────────────────────────────
    // Legacy scoring from AppLauncher — preserved exactly for 100% backward
    // compatibility with app search.
    // ─────────────────────────────────────────────────────────────────────────
    function scoreLegacy(query, text) {
        if (!text) return -1;
        query = query.toLowerCase();
        text = text.toLowerCase();
        if (query.length === 0) return 0;
        
        let qIdx = 0;
        let tIdx = 0;
        let score = 0;
        let lastMatchIdx = -2;
        
        while (qIdx < query.length && tIdx < text.length) {
            if (query[qIdx] === text[tIdx]) {
                if (lastMatchIdx === tIdx - 1) {
                    score += 5; // contiguous match
                } else {
                    score += 1;
                }
                if (tIdx === 0 || text[tIdx - 1] === ' ' || text[tIdx - 1] === '-') {
                    score += 10; // word boundary
                }
                lastMatchIdx = tIdx;
                qIdx++;
            }
            tIdx++;
        }
        
        if (qIdx === query.length) {
            score -= text.length * 0.1; // penalize longer strings
            if (text.startsWith(query)) score += 20;
            return score;
        }
        return -1;
    }

    function _isWordBoundary(c) {
        return c === ' ' || c === '-' || c === '_';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tiered scoring engine for structured emoji search:
    // Exact word > Prefix > Contiguous substring > Subsequence (if >= minSubseqLen)
    // High-performance indexOf implementation without runtime RegExp allocation.
    // ─────────────────────────────────────────────────────────────────────────
    function scoreTiered(token, textLc, minSubseqLen) {
        if (!textLc || !token) return -1;
        const tLen = token.length;
        const sLen = textLc.length;
        if (tLen === 0) return 0;
        
        const minLen = (minSubseqLen !== undefined) ? minSubseqLen : 4;

        // 1. Exact match
        if (textLc === token) {
            return 120.0;
        }

        // 2. Exact word match within text (e.g. "cat" in "grinning cat face")
        let idx = textLc.indexOf(token);
        while (idx !== -1) {
            const before = (idx === 0) || _isWordBoundary(textLc.charAt(idx - 1));
            const after = (idx + tLen === sLen) || _isWordBoundary(textLc.charAt(idx + tLen));
            if (before && after) {
                return 90.0 - (sLen * 0.05);
            }
            idx = textLc.indexOf(token, idx + 1);
        }

        // 3. Prefix match at start of string or start of a word
        if (textLc.startsWith(token)) {
            return 70.0 - (sLen * 0.05);
        }
        let pIdx = textLc.indexOf(token);
        while (pIdx !== -1) {
            if (pIdx > 0 && _isWordBoundary(textLc.charAt(pIdx - 1))) {
                return 60.0 - (sLen * 0.05);
            }
            pIdx = textLc.indexOf(token, pIdx + 1);
        }

        // 4. Contiguous substring match
        const subIdx = textLc.indexOf(token);
        if (subIdx !== -1) {
            return 40.0 - (subIdx * 0.5) - (sLen * 0.05);
        }

        // 5. Subsequence matching (only if token is at least minLen characters)
        if (tLen >= minLen) {
            let qIdx = 0;
            let tIdx = 0;
            let subScore = 0;
            let lastMatch = -2;

            while (qIdx < tLen && tIdx < sLen) {
                if (token[qIdx] === textLc[tIdx]) {
                    subScore += (lastMatch === tIdx - 1) ? 3 : 1;
                    if (tIdx === 0 || _isWordBoundary(textLc.charAt(tIdx - 1))) {
                        subScore += 4;
                    }
                    lastMatch = tIdx;
                    qIdx++;
                }
                tIdx++;
            }

            if (qIdx === tLen) {
                return 15.0 + subScore - (sLen * 0.1);
            }
        }

        return -1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Query preparation (hoisted out of the per-entry loop for high throughput):
    // Trims, lowercases, tokenizes, and strips U+FE0F once per search query.
    // ─────────────────────────────────────────────────────────────────────────
    function prepareQuery(query) {
        if (!query) return null;
        const qTrim = (typeof query === "string") ? query.trim() : "";
        if (qTrim.length === 0) return null;
        return {
            raw: query,
            cleanGlyph: qTrim.replace(/\uFE0F/g, ""),
            tokens: qTrim.toLowerCase().split(/\s+/)
        };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Multi-token emoji scorer:
    // Matches literal emoji glyphs immediately, otherwise requires ALL tokens
    // to match with field weights:
    //   - nameLc:     1.0x
    //   - aliasesLc:  0.9x (higher than tags/keywords)
    //   - keywordsLc: 0.7x
    //   - categoryLc: 0.4x
    // ─────────────────────────────────────────────────────────────────────────
    function scoreEmoji(queryOrPrepared, emojiEntry) {
        if (!queryOrPrepared || !emojiEntry) return 0;
        const pq = (typeof queryOrPrepared === "object" && queryOrPrepared.tokens)
            ? queryOrPrepared
            : prepareQuery(queryOrPrepared);
        if (!pq) return 0;

        // Literal emoji glyph match (using precomputed cleanGlyph if present)
        const entryGlyph = emojiEntry.cleanGlyph || (emojiEntry.emoji ? emojiEntry.emoji.replace(/\uFE0F/g, "") : "");
        if (entryGlyph === pq.cleanGlyph) {
            return 1000.0;
        }

        const tokens = pq.tokens;
        let totalScore = 0;

        for (let i = 0; i < tokens.length; i++) {
            const token = tokens[i];
            let tokenBestScore = -1;

            // 1. Name match (weight 1.0)
            const nScore = scoreTiered(token, emojiEntry.nameLc, 4);
            if (nScore > tokenBestScore) {
                tokenBestScore = nScore * 1.0;
            }

            // 2. Colloquial aliases match (weight 0.9 — outranks plain tags)
            if (emojiEntry.aliasesLc && emojiEntry.aliasesLc.length > 0) {
                for (let a = 0; a < emojiEntry.aliasesLc.length; a++) {
                    const aScore = scoreTiered(token, emojiEntry.aliasesLc[a], 4);
                    if (aScore !== -1 && (aScore * 0.9) > tokenBestScore) {
                        tokenBestScore = aScore * 0.9;
                    }
                }
            }

            // 3. Keywords / tags match (weight 0.7)
            if (emojiEntry.keywordsLc && emojiEntry.keywordsLc.length > 0) {
                for (let k = 0; k < emojiEntry.keywordsLc.length; k++) {
                    const kwScore = scoreTiered(token, emojiEntry.keywordsLc[k], 4);
                    if (kwScore !== -1 && (kwScore * 0.7) > tokenBestScore) {
                        tokenBestScore = kwScore * 0.7;
                    }
                }
            }

            // 4. Category match (weight 0.4)
            const cScore = scoreTiered(token, emojiEntry.categoryLc, 4);
            if (cScore !== -1 && (cScore * 0.4) > tokenBestScore) {
                tokenBestScore = cScore * 0.4;
            }

            // ALL tokens must match!
            if (tokenBestScore === -1) {
                return -1;
            }

            totalScore += tokenBestScore;
        }

        return totalScore;
    }
}
