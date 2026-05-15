export default async function handler(req, res) {
    try {
        const response = await fetch(
            "https://site.web.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
        );

        const data = await response.json();

        const formatAthlete = (
            athlete,
            summary = null
        ) => {
            if (!athlete) {
                return null;
            }

            return {
                id: athlete.id || null,

                name:
                    athlete.displayName ||
                    athlete.fullName ||
                    null,

                shortName:
                    athlete.shortName ||
                    null,

                jersey:
                    athlete.jersey ||
                    null,

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

        const buildPeriodScores = (
            home,
            away
        ) => {
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

                4
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
                            Number(line.period) === period
                    );

                const awayLine =
                    awayLines.find(
                        line =>
                            Number(line.period) === period
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
                        t =>
                            t.homeAway ===
                            "home"
                    );

                const away =
                    comp.competitors.find(
                        t =>
                            t.homeAway ===
                            "away"
                    );

                if (!home || !away) {
                    return null;
                }

                const status =
                    event.status;

                const periodScores =
                    buildPeriodScores(
                        home,
                        away
                    );

                let summaryData =
                    null;

                try {
                    const summaryResponse =
                        await fetch(
                            `https://site.web.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=${event.id}`
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
                    summaryData?.situation ||
                    {};

                const lastPlay =
                    situation.lastPlay ||
                    summaryData?.lastPlay ||
                    null;

                const athlete =
                    situation.athlete ||
                    null;

                const possession =
                    situation.possession ||
                    null;

                return {
                    id: event.id,

                    date: event.date,

                    status:
                        status.type
                            .description,

                    state:
                        status.type
                            .state,

                    clock:
                        status.displayClock,

                    period: {
                        current:
                            status.period,

                        type:
                            status.type
                                .name ===
                                "STATUS_OVERTIME"
                                ? "OT"
                                : "REG",

                        isHalftime:
                            status.type
                                .description ===
                            "Halftime"
                    },

                    live: {
                        homeFouls:
                            Number(
                                home.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "fouls"
                                )?.displayValue || 0
                            ),

                        awayFouls:
                            Number(
                                away.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "fouls"
                                )?.displayValue || 0
                            ),

                        homeTimeouts:
                            Number(
                                home.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "timeoutsRemaining"
                                )?.displayValue || 0
                            ),

                        awayTimeouts:
                            Number(
                                away.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "timeoutsRemaining"
                                )?.displayValue || 0
                            ),

                        possessionTeamId:
                            possession
                                ?.id || null,

                        player:
                            formatAthlete(
                                athlete,
                                situation
                                    ?.description ||
                                null
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
                                        lastPlay
                                            .type
                                            ?.text ||
                                        null,

                                    shortType:
                                        lastPlay
                                            .type
                                            ?.abbreviation ||
                                        null,

                                    teamId:
                                        lastPlay
                                            .team
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
                            home.team
                                .displayName,

                        abbreviation:
                            home.team
                                .abbreviation,

                        logo:
                            home.team
                                .logo,

                        score:
                            Number(
                                home.score ||
                                0
                            ),

                        record:
                            home.records?.[0]
                                ?.summary ||
                            null,

                        fouls:
                            Number(
                                home.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "fouls"
                                )?.displayValue || 0
                            ),

                        timeouts:
                            Number(
                                home.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "timeoutsRemaining"
                                )?.displayValue || 0
                            )
                    },

                    awayTeam: {
                        id:
                            away.team.id,

                        name:
                            away.team
                                .displayName,

                        abbreviation:
                            away.team
                                .abbreviation,

                        logo:
                            away.team
                                .logo,

                        score:
                            Number(
                                away.score ||
                                0
                            ),

                        record:
                            away.records?.[0]
                                ?.summary ||
                            null,

                        fouls:
                            Number(
                                away.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "fouls"
                                )?.displayValue || 0
                            ),

                        timeouts:
                            Number(
                                away.statistics?.find(
                                    stat =>
                                        stat.name ===
                                        "timeoutsRemaining"
                                )?.displayValue || 0
                            )
                    },

                    venue: {
                        name:
                            comp.venue
                                ?.fullName ||
                            "",

                        city:
                            comp.venue
                                ?.address
                                ?.city ||
                            "",

                        state:
                            comp.venue
                                ?.address
                                ?.state ||
                            ""
                    },

                    broadcasts:
                        comp.broadcasts
                            ?.flatMap(
                                b =>
                                    b.names ||
                                    []
                            )
                            .filter(
                                Boolean
                            ) || [],

                    gameLink:
                        event.links?.[0]
                            ?.href ||
                        null
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
            error: "failed"
        });
    }
}