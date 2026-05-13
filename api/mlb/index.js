export default async function handler(req, res) {
    try {
        const scoreboardResponse = await fetch(
            "https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard"
        );

        const scoreboardData = await scoreboardResponse.json();

        const formatAthlete = (athlete, summary = null, stats = null) => {
            if (!athlete) {
                return null;
            }

            return {
                id: athlete.id || null,
                name: athlete.displayName || athlete.fullName || null,
                shortName: athlete.shortName || null,
                jersey: athlete.jersey || null,
                headshot:
                    typeof athlete.headshot === "string"
                        ? athlete.headshot
                        : athlete.headshot?.href || null,
                position:
                    typeof athlete.position === "string"
                        ? athlete.position
                        : athlete.position?.abbreviation || null,
                teamId: athlete.team?.id || null,
                summary,
                stats
            };
        };

        const getStatValue = (stats = [], names = []) => {
            const found = stats.find(stat => names.includes(stat.name));

            return found
                ? {
                    value: found.value ?? null,
                    displayValue: found.displayValue ?? null
                }
                : null;
        };

        const addAthletesToMap = (value, athleteMap, playerStatsMap) => {
            if (!value || typeof value !== "object") {
                return;
            }

            if (value.athlete?.id) {
                athleteMap[String(value.athlete.id)] = value.athlete;

                if (Array.isArray(value.stats)) {
                    playerStatsMap[String(value.athlete.id)] = value.stats;
                }
            }

            if (value.id && value.displayName) {
                athleteMap[String(value.id)] = value;
            }

            if (Array.isArray(value)) {
                for (const item of value) {
                    addAthletesToMap(item, athleteMap, playerStatsMap);
                }

                return;
            }

            for (const key of Object.keys(value)) {
                addAthletesToMap(value[key], athleteMap, playerStatsMap);
            }
        };

        const getPlayerId = (player) => {
            if (!player || player === true) {
                return null;
            }

            return String(
                player.playerId ||
                player.athlete?.id ||
                player.id ||
                ""
            ) || null;
        };

        const getRunner = (base, primaryRunner, fallbackRunner, athleteMap) => {
            const playerId =
                getPlayerId(primaryRunner) ||
                getPlayerId(fallbackRunner);

            const athlete =
                primaryRunner?.athlete ||
                fallbackRunner?.athlete ||
                athleteMap[playerId];

            if (!primaryRunner && !fallbackRunner) {
                return null;
            }

            return {
                base,
                id: playerId || athlete?.id || null,
                name: athlete?.displayName || athlete?.fullName || null,
                shortName: athlete?.shortName || null,
                jersey: athlete?.jersey || null,
                headshot:
                    typeof athlete?.headshot === "string"
                        ? athlete.headshot
                        : athlete?.headshot?.href || null,
                position:
                    typeof athlete?.position === "string"
                        ? athlete.position
                        : athlete?.position?.abbreviation || null
            };
        };

        const parseProbabilityPercent = (text) => {
            const match = text?.match(/([\d.]+)%/);

            return match
                ? Number(match[1])
                : null;
        };

        const parseAtBatPitchCount = (lastPlay) => {
            const match = lastPlay?.text?.match(/Pitch\s+(\d+)/i);

            return match
                ? Number(match[1])
                : null;
        };

        const games = await Promise.all(
            scoreboardData.events.map(async (event) => {
                const comp = event.competitions?.[0];

                if (!comp) {
                    return null;
                }

                const home = comp.competitors.find(
                    team => team.homeAway === "home"
                );

                const away = comp.competitors.find(
                    team => team.homeAway === "away"
                );

                if (!home || !away) {
                    return null;
                }

                const detail =
                    event.status?.type?.detail ||
                    comp.status?.type?.detail ||
                    "";

                const lower = detail.toLowerCase();

                let inningHalf = null;

                if (lower.includes("top")) {
                    inningHalf = "top";
                }
                else if (lower.includes("bottom")) {
                    inningHalf = "bottom";
                }
                else if (lower.includes("mid")) {
                    inningHalf = "mid";
                }
                else if (lower.includes("end")) {
                    inningHalf = "end";
                }

                const isActiveAtBat =
                    inningHalf === "top" ||
                    inningHalf === "bottom";

                let liveData = {
                    balls: 0,
                    strikes: 0,
                    outs: 0,
                    pitchCount: null,
                    atBatPitchCount: null,
                    batter: null,
                    pitcher: null,
                    bases: {
                        first: false,
                        second: false,
                        third: false
                    },
                    runners: [],
                    probabilities: {
                        score1Plus: null,
                        score1PlusPercent: null,
                        score2Plus: null,
                        score2PlusPercent: null
                    },
                    lastPlay: null
                };

                try {
                    const summaryResponse = await fetch(
                        `https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/summary?event=${event.id}`
                    );

                    const summaryData = await summaryResponse.json();

                    const athleteMap = {};
                    const playerStatsMap = {};

                    addAthletesToMap(scoreboardData, athleteMap, playerStatsMap);
                    addAthletesToMap(event, athleteMap, playerStatsMap);
                    addAthletesToMap(comp, athleteMap, playerStatsMap);
                    addAthletesToMap(summaryData, athleteMap, playerStatsMap);

                    const scoreboardSituation = comp.situation || {};
                    const summarySituation = summaryData?.situation || {};

                    const situation = {
                        ...scoreboardSituation,
                        ...summarySituation,
                        pitcher:
                            scoreboardSituation.pitcher ||
                            summarySituation.pitcher,
                        batter:
                            scoreboardSituation.batter ||
                            summarySituation.batter,
                        onFirst:
                            summarySituation.onFirst ||
                            scoreboardSituation.onFirst,
                        onSecond:
                            summarySituation.onSecond ||
                            scoreboardSituation.onSecond,
                        onThird:
                            summarySituation.onThird ||
                            scoreboardSituation.onThird,
                        situationNotes:
                            summarySituation.situationNotes ||
                            scoreboardSituation.situationNotes ||
                            [],
                        lastPlay:
                            scoreboardSituation.lastPlay ||
                            summarySituation.lastPlay
                    };

                    if (Object.keys(situation).length > 0) {
                        const pitcherId = getPlayerId(situation.pitcher);
                        const batterId = getPlayerId(situation.batter);

                        const pitcherAthlete =
                            situation.pitcher?.athlete ||
                            athleteMap[pitcherId] ||
                            null;

                        const batterAthlete =
                            situation.batter?.athlete ||
                            athleteMap[batterId] ||
                            null;

                        const pitcherStats =
                            playerStatsMap[pitcherId] || [];

                        const batterStats =
                            playerStatsMap[batterId] || [];

                        const firstRunner = getRunner(
                            1,
                            summarySituation.onFirst,
                            scoreboardSituation.onFirst,
                            athleteMap
                        );

                        const secondRunner = getRunner(
                            2,
                            summarySituation.onSecond,
                            scoreboardSituation.onSecond,
                            athleteMap
                        );

                        const thirdRunner = getRunner(
                            3,
                            summarySituation.onThird,
                            scoreboardSituation.onThird,
                            athleteMap
                        );

                        const runners = [
                            firstRunner,
                            secondRunner,
                            thirdRunner
                        ].filter(Boolean);

                        const notes = situation.situationNotes || [];

                        const score1Plus = notes.find(
                            note => note.type === "CHANCES_TO_SCORE_1PLUS"
                        );

                        const score2Plus = notes.find(
                            note => note.type === "CHANCES_TO_SCORE_2PLUS"
                        );

                        const lastPlay = situation.lastPlay || null;

                        const pitcherPitchStat = getStatValue(
                            pitcherStats,
                            ["pitches"]
                        );

                        liveData = {
                            balls: Number(situation.balls ?? 0),

                            strikes: Number(situation.strikes ?? 0),

                            outs: Number(situation.outs ?? 0),

                            pitchCount:
                                pitcherPitchStat?.value ??
                                null,

                            atBatPitchCount:
                                parseAtBatPitchCount(lastPlay),

                            batter: formatAthlete(
                                batterAthlete,
                                situation.batter?.summary || null,
                                {
                                    atBats: getStatValue(batterStats, ["atBats"]),
                                    hits: getStatValue(batterStats, ["hits"]),
                                    runs: getStatValue(batterStats, ["runs"]),
                                    rbis: getStatValue(batterStats, ["RBIs"]),
                                    pitchesSeen: getStatValue(batterStats, ["pitches"])
                                }
                            ),

                            pitcher: formatAthlete(
                                pitcherAthlete,
                                situation.pitcher?.summary || null,
                                {
                                    pitches: pitcherPitchStat,
                                    strikeouts: getStatValue(pitcherStats, ["strikeouts"]),
                                    walks: getStatValue(pitcherStats, ["walks"]),
                                    earnedRuns: getStatValue(pitcherStats, ["earnedRuns"]),
                                    hitsAllowed: getStatValue(pitcherStats, ["hits"])
                                }
                            ),

                            bases: {
                                first: !!situation.onFirst,
                                second: !!situation.onSecond,
                                third: !!situation.onThird
                            },

                            runners,

                            probabilities: {
                                score1Plus:
                                    score1Plus?.text || null,

                                score1PlusPercent:
                                    parseProbabilityPercent(score1Plus?.text),

                                score2Plus:
                                    score2Plus?.text || null,

                                score2PlusPercent:
                                    parseProbabilityPercent(score2Plus?.text)
                            },

                            lastPlay: lastPlay
                                ? {
                                    id: lastPlay.id || null,
                                    text: lastPlay.text || null,
                                    type: lastPlay.type?.text || null,
                                    shortType: lastPlay.type?.abbreviation || null,
                                    playType: lastPlay.type?.type || null,
                                    scoreValue: lastPlay.scoreValue ?? null,
                                    teamId: lastPlay.team?.id || null
                                }
                                : null
                        };
                    }
                }
                catch (liveErr) {
                    console.log("LIVE DATA FAILED:", event.id);
                    console.log(liveErr);
                }

                return {
                    id: event.id,
                    uid: event.uid,
                    name: event.name,
                    shortName: event.shortName,
                    date: event.date,
                    season: event.season,

                    status:
                        event.status?.type?.description ||
                        comp.status?.type?.description ||
                        null,

                    state:
                        event.status?.type?.state ||
                        comp.status?.type?.state ||
                        null,

                    completed:
                        event.status?.type?.completed ||
                        comp.status?.type?.completed ||
                        false,

                    clock:
                        event.status?.displayClock ||
                        comp.status?.displayClock ||
                        null,

                    period: {
                        current:
                            event.status?.period ||
                            comp.status?.period ||
                            null,

                        type:
                            event.status?.type?.name ||
                            comp.status?.type?.name ||
                            null,

                        inningHalf,
                        isHalftime: false
                    },

                    inningDisplay:
                        inningHalf &&
                        (
                            event.status?.period ||
                            comp.status?.period
                        )
                            ? `${inningHalf.charAt(0).toUpperCase()}${inningHalf.slice(1)} ${
                                event.status?.period ||
                                comp.status?.period
                            }`
                            : null,

                    live: {
                        isActiveAtBat,

                        balls:
                            isActiveAtBat
                                ? liveData.balls
                                : null,

                        strikes:
                            isActiveAtBat
                                ? liveData.strikes
                                : null,

                        outs:
                            isActiveAtBat
                                ? liveData.outs
                                : null,

                        pitchCount:
                            isActiveAtBat
                                ? liveData.pitchCount
                                : null,

                        atBatPitchCount:
                            isActiveAtBat
                                ? liveData.atBatPitchCount
                                : null,

                        batter:
                            isActiveAtBat
                                ? liveData.batter
                                : null,

                        pitcher:
                            isActiveAtBat
                                ? liveData.pitcher
                                : null,

                        bases:
                            isActiveAtBat
                                ? liveData.bases
                                : {
                                    first: false,
                                    second: false,
                                    third: false
                                },

                        runners:
                            isActiveAtBat
                                ? liveData.runners
                                : [],

                        probabilities:
                            liveData.probabilities,

                        lastPlay:
                            liveData.lastPlay,

                        basesLoaded:
                            isActiveAtBat &&
                            liveData.bases.first &&
                            liveData.bases.second &&
                            liveData.bases.third,

                        runnersInScoringPosition:
                            isActiveAtBat &&
                            (
                                liveData.bases.second ||
                                liveData.bases.third
                            )
                    },

                    homeTeam: {
                        id: home.team.id,
                        name: home.team.displayName,
                        abbreviation: home.team.abbreviation,
                        logo: home.team.logo,
                        score: Number(home.score || 0),
                        hits: home.hits ?? null,
                        errors: home.errors ?? null,
                        records: home.records || []
                    },

                    awayTeam: {
                        id: away.team.id,
                        name: away.team.displayName,
                        abbreviation: away.team.abbreviation,
                        logo: away.team.logo,
                        score: Number(away.score || 0),
                        hits: away.hits ?? null,
                        errors: away.errors ?? null,
                        records: away.records || []
                    },

                    venue:
                        comp.venue?.fullName || null,

                    broadcasts:
                        comp.broadcasts
                            ?.flatMap(broadcast => broadcast.names || [])
                            .filter(Boolean) || [],

                    gameLink:
                        event.links?.[0]?.href || null
                };
            })
        );

        res.setHeader("Access-Control-Allow-Origin", "*");

        res.status(200).json(
            games.filter(Boolean)
        );
    }
    catch (err) {
        console.error(err);

        res.status(500).json({
            error: "failed to fetch mlb games"
        });
    }
}