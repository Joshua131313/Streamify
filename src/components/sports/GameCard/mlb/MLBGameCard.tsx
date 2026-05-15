import React, {
  useState,
} from "react";

import "./MLBGameCard.css";
import "../SportCard.css";

import type {
  GameProps
} from "../../../../types/sports/sportsTypes";

import type {
  IMLBGame
} from "../../../../types/sports/mlbTypes";

import {
  mlbTeamsMap
} from "../../../../data/sports/mlbData";

import {
  useGameCard
} from "../useGameCard";

import {
  MLBGameCardHeader
} from "./components/MLBGameCardHeader";

import {
  MLBGameCardPregame
} from "./components/MLBGameCardPregame";

import {
  MLBGameCardLiveInfo
} from "./components/MLBGameCardLiveInfo";

import {
  WatchButton
} from "../../../ui/Button/WatchButton";

import ExternalGameInfoButton from "../../../ui/Button/ExternalGameInfoButton";
import { MLBGameCardLinescore } from "./components/MLBGameCardLinescore";
import { useSports } from "../../../../context/SportsContext";

interface Props {
  game: IMLBGame;

  card: GameProps;

  showSportName?: boolean;

  className?: string;
}

export const MLBGameCard: React.FC<Props> = ({
  game,
  card,
  className = "",
}) => {

  const [
    showScoreboard,
    setShowScoreboard
  ] = useState(false);

  const { layout } = useSports();

  const {
    openContextMenu,
    defaultSportStreamProvider,
    showPlayButtons,
  } = useGameCard(card);

  const isPregame =
    game.state === "pre";

  const isFinal =
    game.state === "post" ||
    game.completed ||
    card.status === "FINAL";

  const isLive =
    !isPregame &&
    !isFinal;

  const shouldShowScoreboard =
    isFinal ||
    (
      isLive &&
      showScoreboard
    );

  const awayColor =
    mlbTeamsMap[
      card.awayTeam.abbrev
    ]?.color ??
    "#2563eb";

  const homeColor =
    mlbTeamsMap[
      card.homeTeam.abbrev
    ]?.color ??
    "#dc2626";

  const inningsPlayed =
    game.live?.linescore?.length ?? 9;

  const startTime =
    new Date(game.date).toLocaleTimeString(
      [],
      {
        hour: "numeric",
        minute: "2-digit",
      }
    );

  return (
    <article
      className={`${className} mlb-game-card sport-game-card`}
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

      <MLBGameCardHeader
        game={game}
        card={card}
        showScoreboard={showScoreboard}
        setShowScoreboard={setShowScoreboard}
      />

      <section className="sport-card-bottom">

        {isPregame ? (

          <MLBGameCardPregame
            startTime={startTime}
          />

        ) : (

          <>
            {layout === "list" ? (

              <>
                {
                  isLive &&
                  <MLBGameCardLiveInfo
                    game={game}
                    card={card}
                  />

                }
                <MLBGameCardLinescore
                  game={game}
                  card={card}
                />
              </>

            ) : (

              shouldShowScoreboard ? (

                <MLBGameCardLinescore
                  game={game}
                  card={card}
                />

              ) : (

                <MLBGameCardLiveInfo
                  game={game}
                  card={card}
                />

              )

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

export default MLBGameCard;