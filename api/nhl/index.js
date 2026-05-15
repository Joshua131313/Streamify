export default async function handler(req, res) {
    try {
        const response = await fetch(
            "https://site.web.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard"
        );

        const data = await response.json();

        const formatAthlete = (athlete, summary = null) => {
            if (!athlete) return null;

            return {
                id: athlete.id || null,
                name: athlete.displayName || athlete.fullName || null,
                shortName: athlete.shortName || null,
                jersey: athlete.jersey || null,
                position:
                    typeof athlete.position === "string"
                        ? athlete.position
                        : athlete.position?.abbreviation || null,
                headshot:
                    typeof athlete.headshot === "string"
                        ? athlete.headshot
                        : athlete.headshot?.href || null,
                summary
            };
        };

        const getStatValue = (stats = [], keys = []) => {
            const lowered = keys.map(key =>
                String(key).toLowerCase()
            );

            const found = stats.find(stat => {
                const possibleKeys = [
                    stat.name,
                    stat.label,
                    stat.displayName,
                    stat.shortDisplayName,
                    stat.abbreviation
                ]
                    .filter(Boolean)
                    .map(value =>
                        String(value).toLowerCase()
                    );

                return possibleKeys.some(key =>
                    lowered.includes(key)
                );
            });

            return found?.displayValue ?? null;
        };

        const parseClockToSeconds = clock => {
            if (!clock || typeof clock !== "string") {
                return null;
            }

            const parts = clock.split(":");

            if (parts.length !== 2) {
                return null;
            }

            const minutes = Number(parts[0]);
            const seconds = Number(parts[1]);

            if (
                Number.isNaN(minutes) ||
                Number.isNaN(seconds)
            ) {
                return null;
            }

            return (minutes * 60) + seconds;
        };

        const formatSecondsToClock = totalSeconds => {
            if (
                totalSeconds == null ||
                totalSeconds <= 0
            ) {
                return null;
            }

            const minutes =
                Math.floor(totalSeconds / 60);

            const seconds =
                totalSeconds % 60;

            return `${minutes}:${String(seconds).padStart(2, "0")}`;
        };

        const getPeriodLengthSeconds = period => {
            return period >= 4
                ? 300
                : 1200;
        };

        const getGameElapsedSeconds = (
            period,
            clock
        ) => {
            const remaining =
                parseClockToSeconds(clock);

            if (
                remaining == null ||
                !period
            ) {
                return null;
            }

            let elapsed = 0;

            for (let i = 1; i < period; i++) {
                elapsed +=
                    getPeriodLengthSeconds(i);
            }

            elapsed +=
                getPeriodLengthSeconds(period) -
                remaining;

            return elapsed;
        };

        const getPlayClock = play => {
            return (
                play.clock?.displayValue ||
                play.clock?.value ||
                play.clock ||
                play.displayClock ||
                play.time ||
                null
            );
        };

        const getPlayPeriod = play => {
            return Number(
                play.period?.number ||
                play.period?.value ||
                play.period ||
                play.periodNumber ||
                0
            );
        };

        const getPlayTeamId = play => {
            return (
                play.team?.id ||
                play.participants?.[0]?.team?.id ||
                play.athletesInvolved?.[0]?.team?.id ||
                null
            );
        };

        const getPenaltyMinutes = play => {
            const direct =
                play.penaltyMinutes ||
                play.penalty?.minutes ||
                play.minutes ||
                null;

            if (direct != null) {
                const parsed = Number(direct);

                return Number.isNaN(parsed)
                    ? null
                    : parsed;
            }

            const text = [
                play.text,
                play.shortText,
                play.displayText,
                play.description
            ]
                .filter(Boolean)
                .join(" ");

            const match =
                text.match(
                    /(\d+)\s*(min|minute|minutes)/i
                );

            if (!match) {
                return 2;
            }

            return Number(match[1]);
        };

        const normalizeStrength = strength => {
            if (!strength) {
                return null;
            }

            const match = String(strength)
                .replace(/\s+/g, "")
                .match(/(\d)[- ]?on[- ]?(\d)/i);

            if (!match) {
                return null;
            }

            return {
                homeSkaters: Number(match[1]),
                awaySkaters: Number(match[2])
            };
        };

        const isPenaltyPlay = play => {
            const text = [
                play.text,
                play.shortText,
                play.displayText,
                play.description,
                play.type?.text,
                play.type?.name,
                play.type?.abbreviation
            ]
                .filter(Boolean)
                .join(" ")
                .toLowerCase();

            return (
                text.includes("penalty") ||
                text.includes("minor") ||
                text.includes("bench minor") ||
                text.includes("double minor") ||
                text.includes("hooking") ||
                text.includes("tripping") ||
                text.includes("slashing") ||
                text.includes("holding") ||
                text.includes("roughing") ||
                text.includes("cross checking") ||
                text.includes("cross-checking") ||
                text.includes("high sticking") ||
                text.includes("high-sticking") ||
                text.includes("interference") ||
                text.includes("delay of game") ||
                text.includes("too many men") ||
                text.includes("boarding") ||
                text.includes("charging")
            );
        };

        const flattenPlays = value => {
            const plays = [];

            const walk = current => {
                if (!current) {
                    return;
                }

                if (Array.isArray(current)) {
                    current.forEach(walk);
                    return;
                }

                if (typeof current !== "object") {
                    return;
                }

                const hasClock =
                    current.clock?.displayValue ||
                    current.clock?.value ||
                    current.displayClock ||
                    current.time;

                const hasPeriod =
                    current.period?.number ||
                    current.period?.value ||
                    current.period ||
                    current.periodNumber;

                const hasType =
                    current.type?.text ||
                    current.type?.name ||
                    current.type?.abbreviation;

                const hasText =
                    current.text ||
                    current.shortText ||
                    current.displayText ||
                    current.description;

                if (
                    current.id &&
                    (
                        hasClock ||
                        hasPeriod ||
                        hasType ||
                        hasText
                    )
                ) {
                    plays.push(current);
                }

                Object.values(current)
                    .forEach(walk);
            };

            walk(value);

            return plays;
        };

        const buildActivePowerPlayFromSituation = ({
            situation,
            home,
            away
        }) => {
            if (!situation) {
                return null;
            }

            const strengthText =
                situation.strength ||
                situation.playDescription ||
                situation.summary ||
                situation.situation ||
                null;

            const parsedStrength =
                normalizeStrength(strengthText);

            const homeSkaters =
                parsedStrength?.homeSkaters ??
                null;

            const awaySkaters =
                parsedStrength?.awaySkaters ??
                null;

            const advantageTeamId =
                situation.team?.id ||
                situation.onIceAdvantage?.id ||
                null;

            const clock =
                situation.clock ||
                situation.timeRemaining ||
                situation.displayClock ||
                null;

            const isPowerPlay =
                homeSkaters != null &&
                awaySkaters != null &&
                homeSkaters !== awaySkaters;

            const isEvenStrength =
                homeSkaters != null &&
                awaySkaters != null &&
                homeSkaters === awaySkaters;

            if (
                !strengthText &&
                !advantageTeamId &&
                !clock &&
                homeSkaters == null &&
                awaySkaters == null
            ) {
                return null;
            }

            return {
                strength:
                    strengthText ||
                    (
                        homeSkaters != null &&
                        awaySkaters != null
                            ? `${homeSkaters}-on-${awaySkaters}`
                            : null
                    ),

                display:
                    strengthText ||
                    (
                        homeSkaters != null &&
                        awaySkaters != null
                            ? `${homeSkaters}-on-${awaySkaters}`
                            : null
                    ),

                clock,

                advantageTeamId,

                advantageTeamAbbreviation:
                    advantageTeamId === home.team.id
                        ? home.team.abbreviation
                        : advantageTeamId === away.team.id
                            ? away.team.abbreviation
                            : null,

                homeSkaters,
                awaySkaters,

                isPowerPlay,
                isEvenStrength,

                isEmptyNet:
                    String(strengthText || "")
                        .toLowerCase()
                        .includes("empty")
            };
        };

        const buildActivePowerPlayFromPlays = ({
            summaryData,
            home,
            away,
            currentPeriod,
            currentClock
        }) => {
            const currentElapsed =
                getGameElapsedSeconds(
                    currentPeriod,
                    currentClock
                );

            if (currentElapsed == null) {
                return null;
            }

            const allPlays = flattenPlays([
                summaryData?.plays,
                summaryData?.allPlays,
                summaryData?.playByPlay,
                summaryData?.drives,
                summaryData?.drives?.previousPlays,
                summaryData?.drives?.currentPlay,
                summaryData?.scoringPlays,
                summaryData?.header,
                summaryData
            ]);

            const penaltyPlays = allPlays
                .filter(isPenaltyPlay)
                .map(play => {
                    const period =
                        getPlayPeriod(play);

                    const clock =
                        getPlayClock(play);

                    const teamId =
                        getPlayTeamId(play);

                    const minutes =
                        getPenaltyMinutes(play);

                    const startElapsed =
                        getGameElapsedSeconds(
                            period,
                            clock
                        );

                    if (
                        !teamId ||
                        startElapsed == null
                    ) {
                        return null;
                    }

                    return {
                        id: play.id,
                        teamId,
                        minutes,
                        startElapsed,
                        endElapsed:
                            startElapsed +
                            (minutes * 60),

                        text:
                            play.text ||
                            play.shortText ||
                            play.displayText ||
                            play.description ||
                            null
                    };
                })
                .filter(Boolean);

            if (!penaltyPlays.length) {
                return null;
            }

            const activePenalties =
                penaltyPlays.filter(
                    penalty =>
                        penalty.startElapsed <= currentElapsed &&
                        penalty.endElapsed > currentElapsed
                );

            if (!activePenalties.length) {
                return null;
            }

            const homePenaltyCount =
                activePenalties.filter(
                    penalty =>
                        penalty.teamId === home.team.id
                ).length;

            const awayPenaltyCount =
                activePenalties.filter(
                    penalty =>
                        penalty.teamId === away.team.id
                ).length;

            const homeSkaters =
                Math.max(
                    3,
                    5 - homePenaltyCount
                );

            const awaySkaters =
                Math.max(
                    3,
                    5 - awayPenaltyCount
                );

            const isEvenStrength =
                homeSkaters === awaySkaters;

            const isPowerPlay =
                homeSkaters !== awaySkaters;

            if (!isPowerPlay) {
                return null;
            }

            const advantageTeamId =
                homeSkaters > awaySkaters
                    ? home.team.id
                    : away.team.id;

            const remainingSeconds =
                Math.max(
                    ...activePenalties.map(
                        penalty =>
                            penalty.endElapsed -
                            currentElapsed
                    )
                );

            return {
                strength:
                    `${homeSkaters}-on-${awaySkaters}`,

                display:
                    `${homeSkaters}-on-${awaySkaters}`,

                clock:
                    formatSecondsToClock(
                        Math.ceil(
                            remainingSeconds
                        )
                    ),

                advantageTeamId,

                advantageTeamAbbreviation:
                    advantageTeamId === home.team.id
                        ? home.team.abbreviation
                        : away.team.abbreviation,

                homeSkaters,
                awaySkaters,

                isPowerPlay,
                isEvenStrength,

                isEmptyNet: false,

                activePenalties
            };
        };

        const buildPowerPlay = ({
            summaryData,
            situation,
            home,
            away,
            currentPeriod,
            currentClock
        }) => {
            const fromSituation =
                buildActivePowerPlayFromSituation({
                    situation,
                    home,
                    away
                });

            if (fromSituation?.isPowerPlay) {
                return fromSituation;
            }

            const fromPlays =
                buildActivePowerPlayFromPlays({
                    summaryData,
                    home,
                    away,
                    currentPeriod,
                    currentClock
                });

            if (fromPlays?.isPowerPlay) {
                return fromPlays;
            }

            return {
                strength: "5-on-5",
                display: "5-on-5",
                clock: null,
                advantageTeamId: null,
                advantageTeamAbbreviation: null,
                homeSkaters: 5,
                awaySkaters: 5,
                isPowerPlay: false,
                isEvenStrength: true,
                isEmptyNet: false,
                activePenalties: []
            };
        };

        const buildPeriodScores = (home, away) => {
            const homeLines =
                home?.linescores || [];

            const awayLines =
                away?.linescores || [];

            const periodNumbers = [
                ...homeLines.map(
                    line => Number(line.period)
                ),
                ...awayLines.map(
                    line => Number(line.period)
                ),
                3
            ];

            const maxPeriod =
                Math.max(...periodNumbers);

            const periods = [];

            for (
                let period = 1;
                period <= maxPeriod;
                period++
            ) {
                const homeLine =
                    homeLines.find(
                        line =>
                            Number(line.period) ===
                            period
                    );

                const awayLine =
                    awayLines.find(
                        line =>
                            Number(line.period) ===
                            period
                    );

                periods.push({
                    period,

                    home:
                        homeLine?.displayValue != null
                            ? Number(
                                homeLine.displayValue
                            )
                            : null,

                    away:
                        awayLine?.displayValue != null
                            ? Number(
                                awayLine.displayValue
                            )
                            : null
                });
            }

            return periods;
        };

        const games = await Promise.all(
            data.events.map(async event => {
                const comp =
                    event.competitions?.[0];

                if (!comp) {
                    return null;
                }

                const home =
                    comp.competitors.find(
                        team =>
                            team.homeAway ===
                            "home"
                    );

                const away =
                    comp.competitors.find(
                        team =>
                            team.homeAway ===
                            "away"
                    );

                if (!home || !away) {
                    return null;
                }

                const status =
                    event.status;

                const currentPeriod =
                    Number(
                        status.period || 0
                    );

                const currentClock =
                    status.displayClock ||
                    null;

                const periodScores =
                    buildPeriodScores(
                        home,
                        away
                    );

                let summaryData = null;

                try {
                    const summaryResponse =
                        await fetch(
                            `https://site.web.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=${event.id}`
                        );

                    summaryData =
                        await summaryResponse.json();
                }
                catch (err) {
                    console.log(
                        "SUMMARY FAILED:",
                        event.id
                    );

                    console.log(err);
                }

                const situation =
                    summaryData?.header
                        ?.competitions?.[0]
                        ?.situation ||
                    summaryData?.situation ||
                    {};

                const lastPlay =
                    situation.lastPlay ||
                    summaryData?.lastPlay ||
                    null;

                const homeBoxscore =
                    summaryData?.boxscore?.teams?.find(
                        team =>
                            team.homeAway ===
                            "home"
                    );

                const awayBoxscore =
                    summaryData?.boxscore?.teams?.find(
                        team =>
                            team.homeAway ===
                            "away"
                    );

                const homeStats =
                    homeBoxscore?.statistics ||
                    home.statistics ||
                    [];

                const awayStats =
                    awayBoxscore?.statistics ||
                    away.statistics ||
                    [];

                const homeShots =
                    getStatValue(
                        homeStats,
                        [
                            "shotsTotal",
                            "shots",
                            "shotsOnGoal",
                            "S",
                            "SOG"
                        ]
                    );

                const awayShots =
                    getStatValue(
                        awayStats,
                        [
                            "shotsTotal",
                            "shots",
                            "shotsOnGoal",
                            "S",
                            "SOG"
                        ]
                    );

                const homePPGoals =
                    getStatValue(
                        homeStats,
                        [
                            "powerPlayGoals",
                            "PPG"
                        ]
                    );

                const awayPPGoals =
                    getStatValue(
                        awayStats,
                        [
                            "powerPlayGoals",
                            "PPG"
                        ]
                    );

                const homePPOpportunities =
                    getStatValue(
                        homeStats,
                        [
                            "powerPlayOpportunities",
                            "PPO"
                        ]
                    );

                const awayPPOpportunities =
                    getStatValue(
                        awayStats,
                        [
                            "powerPlayOpportunities",
                            "PPO"
                        ]
                    );

                const goalieAthlete =
                    situation.goalie?.athlete ||
                    null;

                const skaterAthlete =
                    situation.skater?.athlete ||
                    null;

                const powerPlay =
                    buildPowerPlay({
                        summaryData,
                        situation,
                        home,
                        away,
                        currentPeriod,
                        currentClock
                    });

                return {
                    id: event.id,
                    date: event.date,

                    status:
                        status.type.description,

                    state:
                        status.type.state,

                    clock:
                        status.displayClock,

                    period: {
                        current:
                            status.period,

                        type:
                            status.type.name ===
                            "STATUS_OVERTIME"
                                ? "OT"
                                : status.type.name ===
                                  "STATUS_SHOOTOUT"
                                    ? "SO"
                                    : "REG",

                        isHalftime:
                            status.type.description ===
                            "Intermission"
                    },

                    live: {
                        homeShots:
                            Number(
                                homeShots || 0
                            ),

                        awayShots:
                            Number(
                                awayShots || 0
                            ),

                        powerPlay,

                        goalie:
                            formatAthlete(
                                goalieAthlete,
                                situation.goalie
                                    ?.summary || null
                            ),

                        skater:
                            formatAthlete(
                                skaterAthlete,
                                situation.skater
                                    ?.summary || null
                            ),

                        lastPlay:
                            lastPlay
                                ? {
                                    id:
                                        lastPlay.id ||
                                        null,

                                    text:
                                        lastPlay.text ||
                                        null,

                                    type:
                                        lastPlay.type
                                            ?.text ||
                                        null,

                                    shortType:
                                        lastPlay.type
                                            ?.abbreviation ||
                                        null,

                                    teamId:
                                        lastPlay.team
                                            ?.id ||
                                        null
                                }
                                : null,

                        periodScores
                    },

                    homeTeam: {
                        id:
                            home.team.id,

                        name:
                            home.team.displayName,

                        abbreviation:
                            home.team.abbreviation,

                        logo:
                            home.team.logo,

                        score:
                            Number(
                                home.score || 0
                            ),

                        shots:
                            Number(
                                homeShots || 0
                            ),

                        powerPlay: {
                            goals:
                                Number(
                                    homePPGoals || 0
                                ),

                            opportunities:
                                Number(
                                    homePPOpportunities || 0
                                )
                        },

                        record:
                            home.records?.[0]
                                ?.summary || null
                    },

                    awayTeam: {
                        id:
                            away.team.id,

                        name:
                            away.team.displayName,

                        abbreviation:
                            away.team.abbreviation,

                        logo:
                            away.team.logo,

                        score:
                            Number(
                                away.score || 0
                            ),

                        shots:
                            Number(
                                awayShots || 0
                            ),

                        powerPlay: {
                            goals:
                                Number(
                                    awayPPGoals || 0
                                ),

                            opportunities:
                                Number(
                                    awayPPOpportunities || 0
                                )
                        },

                        record:
                            away.records?.[0]
                                ?.summary || null
                    },

                    venue:
                        comp.venue?.fullName ||
                        null,

                    broadcasts:
                        comp.broadcasts
                            ?.flatMap(
                                b => b.names || []
                            )
                            .filter(Boolean) || [],

                    gameLink:
                        event.links?.[0]
                            ?.href || null
                };
            })
        );

        res.setHeader(
            "Access-Control-Allow-Origin",
            "*"
        );

        res.status(200).json(
            games.filter(Boolean)
        );
    }
    catch (err) {
        console.error(err);

        res.status(500).json({
            error: "failed to fetch nhl games"
        });
    }
}