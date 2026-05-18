import React, {
  useState,
} from "react";
import "./NHLGameCard.css"
import "../SportCard.css"

import type { GameProps } from "../../../../types/sports/sportsTypes";
import type { INHLGame } from "../../../../types/sports/nhlTypes";

import { nhlTeamsMap } from "../../../../data/sports/nhlData";

import { useGameCard } from "../useGameCard";
import { GameCardTeam } from "../GameCardTeam";

import { WatchButton } from "../../../ui/Button/WatchButton";
import ExternalGameInfoButton from "../../../ui/Button/ExternalGameInfoButton";
import { getOrdinalSuffix } from "../../../../utils/sports/sportsUtils";
import { PeriodGroup } from "../PeriodGroup";
import { DateTime } from "luxon";

interface Props {
  game: INHLGame;
  card: GameProps;
  showSportName?: boolean;
  className?: string;
}

export const NHLGameCard: React.FC<Props> = ({
  game,
  card,
  className = "",
}) => {
  console.log(game)
  const [showScoreboard] =
    useState(true);

  const {
    openContextMenu,
    defaultSportStreamProvider,
    showPlayButtons,
    leadingTeam,
  } = useGameCard(card);

  const isPregame =
    game.state === "pre";

  const isFinal =
    game.state === "post";

  const isLive =
    !isPregame &&
    !isFinal;

  const awayColor =
    nhlTeamsMap[
      card.awayTeam.abbrev
    ]?.color ??
    "#2563eb";

  const homeColor =
    nhlTeamsMap[
      card.homeTeam.abbrev
    ]?.color ??
    "#dc2626";

  const currentPeriod =
    game.period?.current;

  const periodText =
    isPregame
      ? DateTime.fromISO(game.date).toFormat("MMM d")
      : game.period.type === "SO"
        ? "Shootout"
        : game.period.type === "OT"
          ? `OT ${currentPeriod}`
          : isFinal
            ? "Final"
            : `${currentPeriod}${getOrdinalSuffix(currentPeriod)}`;

  const lastPlay =
    game.live?.lastPlay;

  const player =
    game.live?.skater ||
    game.live?.goalie;

  const startTime =
    new Date(game.date).toLocaleTimeString(
      [],
      {
        hour: "numeric",
        minute: "2-digit",
      }
    );
const basePeriods =
    game.live?.periodScores?.length ?? 3;

const extraPeriods =
    (game.period.type === "OT" ? 1 : 0) +
    (game.period.type === "SO" ? 1 : 0);

const periodsPlayed =
    basePeriods + extraPeriods;
    
  return (
    <article
      className={`${className} sport-game-card`}
      onContextMenu={openContextMenu}
      style={{
        ["--away-color" as string]:
          awayColor,

        ["--home-color" as string]:
          homeColor,

        ["--away-logo" as string]:
          `url(${card.awayTeam.logo})`,

        ["--home-logo" as string]:
          `url(${card.homeTeam.logo})`,
      }}
    >

      <section className="sport-card-top">

        <div className="sport-card-backdrop-logo away" />

        <div className="sport-card-backdrop-logo home" />

        <div className="sport-card-team-glow away" />

        <div className="sport-card-team-glow home" />

        <div className="sport-scoreboard-grid">

          <div className="sport-team-column away">

            <GameCardTeam
              game={card}
              leadingTeam={leadingTeam}
              teamKey="awayTeam"
            />

            <div className="sport-team-abbrev">
              {card.awayTeam.abbrev}
            </div>

          </div>

          <div className="sport-center-column">

            <div className="sport-inning-row">


              <span>
                {periodText}
              </span>

            </div>

            <div className="sport-count-row">

              {isPregame
                ? game.venue ?? "NHL"

                : isFinal
                  ? game.broadcasts?.[0] ?? "NHL"

                  : game.clock}

            </div>

            {!isPregame && (
              <div
                style={{
                  marginTop: 14,
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 6,
                }}
              >

                <span
                  style={{
                    fontSize: ".72rem",
                    fontWeight: 800,
                    opacity: .7,
                    letterSpacing: 1,
                  }}
                >
                  SHOTS
                </span>

                <div
                  style={{
                    display: "flex",
                    gap: 12,
                    alignItems: "center",
                    fontWeight: 900,
                    fontSize: "1rem",
                  }}
                >

                  <span>
                    {game.live?.awayShots ?? "-"}
                  </span>

                  <span
                    style={{
                      opacity: .4,
                    }}
                  >
                    -
                  </span>

                  <span>
                    {game.live?.homeShots ?? "-"}
                  </span>

                </div>

              </div>
            )}

          </div>

          <div className="sport-team-column home">

            <GameCardTeam
              game={card}
              leadingTeam={leadingTeam}
              teamKey="homeTeam"
            />

            <div className="sport-team-abbrev">
              {card.homeTeam.abbrev}
            </div>

          </div>

        </div>

      </section>

      <section className="sport-card-bottom">

        {isPregame ? (

          <div className="sport-game-start">

            <span className="sport-game-start-time">
              {startTime}
            </span>

            <span className="sport-game-start-venue">

              {game.broadcasts?.[0] ??
                "ESPN+"}

            </span>

          </div>

        ) : (
          <>
            {lastPlay && (
              <div
                className="sport-live-info"
                style={{
                  marginBottom: 4,
                }}
              >

                <div
                  className="sport-live-line batter"
                >

                  <span className="sport-line-indicator" />

                  {player?.headshot && (
                    <img
                      src={player.headshot}
                      alt={player.name ?? ""}
                      style={{
                        width: 38,
                        height: 38,
                        borderRadius: 999,
                        objectFit: "cover",
                        border: "1px solid var(--border)",
                      }}
                    />
                  )}

                  <div className="sport-player-copy">

                    <span className="sport-player-role">
                      Last Play
                    </span>

                    <span className="sport-player-name">
                      {lastPlay.text}
                    </span>

                  </div>

                </div>

              </div>
            )}

            {showScoreboard && (

              <div className="sport-linescore">

                <div className="sport-linescore-header">

                  <span className="team-cell" />

                  <PeriodGroup
                    periodsPlayed={periodsPlayed}
                  >

                    {game.live?.periodScores?.map(period => (
                      <span
                        key={period.period}
                        className="inning-cell"
                      >
                        {period.period}
                      </span>
                    ))}

                    {game.period.type === "OT" && (
                      <span className="inning-cell">
                        OT
                      </span>
                    )}

                    {game.period.type === "SO" && (
                      <span className="inning-cell">
                        SO
                      </span>
                    )}

                  </PeriodGroup>

                  <div className="nhl-totals-group">

                    <span className="total-cell">
                      G
                    </span>

                    <span className="total-cell">
                      S
                    </span>

                  </div>

                </div>

                <div className="sport-linescore-row">

                  <span className="team-cell">
                    {card.awayTeam.abbrev}
                  </span>

                  <PeriodGroup periodsPlayed={periodsPlayed}>

                    {game.live?.periodScores?.map(period => (
                      <span
                        key={`away-${period.period}`}
                         className={`${Number(period.away) > Number(period.home) ? "greater" : ""} inning-cell`}
                      >
                        {period.away ?? "-"}
                      </span>
                    ))}

                  </PeriodGroup>

                  <div className="nhl-totals-group">

                    <span className="total-cell">
                      {game.awayTeam.score}
                    </span>

                    <span className="total-cell">
                      {game.awayTeam.shots ?? "-"}
                    </span>

                  </div>

                </div>

                <div className="sport-linescore-row">

                  <span className="team-cell">
                    {card.homeTeam.abbrev}
                  </span>

                  <PeriodGroup periodsPlayed={periodsPlayed}>

                    {game.live?.periodScores?.map(period => (
                      <span
                        key={`home-${period.period}`}
                         className={`${Number(period.home) > Number(period.away) ? "greater" : ""} inning-cell`}
                      >
                        {period.home ?? "-"}
                      </span>
                    ))}

                  </PeriodGroup>

                  <div className="nhl-totals-group">

                    <span className="total-cell">
                      {game.homeTeam.score}
                    </span>

                    <span className="total-cell">
                      {game.homeTeam.shots ?? "-"}
                    </span>

                  </div>

                </div>

              </div>

            )}
          </>
        )}

        <div
          className={`game-card-buttons ${!showPlayButtons
            ? "single"
            : ""
            }`}
        >

          <ExternalGameInfoButton
            url={card.gameLink}
          />

          {showPlayButtons && (
            <WatchButton
              variant="button"
              awayTeamAbbrev={
                card.awayTeam.abbrev
              }
              homeTeamAbbrev={
                card.homeTeam.abbrev
              }
              streamProvider={
                defaultSportStreamProvider
              }
              league={card.leagueName}
            />
          )}

        </div>

      </section>

    </article>
  );
};

export default NHLGameCard;