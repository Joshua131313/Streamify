import { useState } from "react";
import { useSports } from "../../../context/SportsContext";
import { mlbTeamsMap } from "../../../data/sports/mlbData";
import { nbaTeamsMap } from "../../../data/sports/nbaData";
import { nhlTeamsMap } from "../../../data/sports/nhlData";
import { SearchableContainer } from "../../layout/Container/SearchableContainer";
import { SidebarCard } from "../GameCard/SidebarCard";
import "./SportsSidebar.css"
import { FaChevronLeft, FaChevronRight } from "react-icons/fa";
import { useEdgeSwipe } from "../../../hooks/utilHooks/useEdgeSwipe";
import { GameGroupCard } from "../GameCard/GameGroupCard";
import { useFavoriteTeamsContext } from "../../../context/FavoriteTeamsContext";
import { wnbaTeamsMap } from "../../../data/sports/wnbaData";

export const SportsSidebar = () => {
    const [show, setShow] = useState(false);
    const { favoriteTeams } = useFavoriteTeamsContext();
    const { liveGames } = useSports();
    const renderedGameIds = new Set<string>();

    useEdgeSwipe({
        onOpen: () => setShow(true),
    });


    return (
        <>
            {show && <div className="sidebar-overlay" onClick={() => setShow(false)}></div>}
            {show &&
                <div className="sports-sidebar">
                    {
                        liveGames.length > 0 &&
                        <SearchableContainer
                            title="Teams Playing Now"
                            data={liveGames}
                            defaultOpened
                            searchFn={(game, search) =>
                                game.card.homeTeam.name.toLowerCase().includes(search) ||
                                game.card.awayTeam.name.toLowerCase().includes(search)
                            }
                            renderItem={(game) => (
                                <GameGroupCard game={game.card} key={game.id} />
                            )}
                        />
                    }
                    <SearchableContainer
                        title="Followed Teams"
                        data={favoriteTeams}
                        defaultOpened
                        searchFn={(team, search) =>
                            team.name.toLowerCase().includes(search) ||
                            team.abbrev.toLowerCase().includes(search)
                        }
                        renderItem={(team) => {
                            const game = liveGames.find(g =>
                                g.card.homeTeam.abbrev === team.abbrev ||
                                g.card.awayTeam.abbrev === team.abbrev
                            );

                            if (!game) {
                                return (
                                    <SidebarCard
                                        key={team.abbrev}
                                        team={team}
                                    />
                                );
                            }

                            const isHome = game.card.homeTeam.abbrev === team.abbrev;
                            const opponent = isHome ? game.card.awayTeam : game.card.homeTeam;

                            const isOpponentFollowed = favoriteTeams.some(
                                t => t.abbrev === opponent.abbrev
                            );

                            if (isOpponentFollowed) {
                                if (renderedGameIds.has(String(game.id))) return null;

                                renderedGameIds.add(String(game.id));

                                return (
                                    <div className="game-group" key={game.id}>
                                        <SidebarCard team={game.card.awayTeam} game={game.card} />
                                        <SidebarCard team={game.card.homeTeam} game={game.card} />
                                    </div>
                                );
                            }

                            return (
                                <SidebarCard
                                    key={team.abbrev}
                                    team={team}
                                    game={game.card}
                                />
                            );
                        }}
                    />
                    <SearchableContainer
                        title="NBA Teams"
                        data={Object.values(nbaTeamsMap)}
                        searchFn={(team, search) =>
                            team.teamName.toLowerCase().includes(search) ||
                            team.abbreviation.toLowerCase().includes(search)
                        }
                        renderItem={(team) => (
                            <SidebarCard
                                key={team.abbreviation}
                                team={{
                                    abbrev: team.abbreviation,
                                    name: team.teamName,
                                    league: team.league
                                }}
                            />
                        )}
                    />
                    <SearchableContainer
                        title="WNBA Teams"
                        data={Object.values(wnbaTeamsMap)}
                        searchFn={(team, search) =>
                            team.teamName.toLowerCase().includes(search) ||
                            team.abbreviation.toLowerCase().includes(search)
                        }
                        renderItem={(team) => (
                            <SidebarCard
                                key={team.abbreviation}
                                team={{
                                    abbrev: team.abbreviation,
                                    name: team.teamName,
                                    league: team.league
                                }}
                            />
                        )}
                    />
                    <SearchableContainer
                        title="NHL Teams"
                        data={Object.values(nhlTeamsMap)}
                        searchFn={(team, search) =>
                            team.teamName.toLowerCase().includes(search) ||
                            team.abbreviation.toLowerCase().includes(search)
                        }
                        renderItem={(team) => (
                            <SidebarCard
                                key={team.abbreviation}
                                team={{
                                    abbrev: team.abbreviation,
                                    name: team.teamName,
                                    league: team.league
                                }}
                            />
                        )}
                    />
                    <SearchableContainer
                        title="MLB Teams"
                        data={Object.values(mlbTeamsMap)}
                        searchFn={(team, search) =>
                            team.teamName.toLowerCase().includes(search) ||
                            team.abbreviation.toLowerCase().includes(search)
                        }
                        renderItem={(team) => (
                            <SidebarCard
                                key={team.abbreviation}
                                team={{
                                    abbrev: team.abbreviation,
                                    name: team.teamName,
                                    league: team.league
                                }}
                            />
                        )}
                    />
                </div>
            }
            <div className={`${show ? "active" : ""} sidebar-toggler sports-sidebar-controller`} onClick={() => setShow(!show)}>
                {show ? <FaChevronLeft /> : <FaChevronRight />}
            </div>
        </>
    );
};