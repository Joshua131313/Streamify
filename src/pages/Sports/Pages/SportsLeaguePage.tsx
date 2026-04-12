import { FilteredSportsContainer } from "../../../components/layout/Container/FilteredSportsContainer";
import SportsLayout from "../SportsLayout";
import type { GameProps, Leagues } from "../../../types/sports/sportsTypes";
import { SportsPlayer } from "../SportsPlayer";
import HorizontalGameCard from "../../../components/ui/GameCard/HorizontalGameCard";

interface SportLeaguePageProps {
    league: Leagues;
    title: string;
    subTitle: string;
    games: GameProps[];
    favoriteGames: GameProps[];
    followedTitle?: string;
    gamesTitle?: string;
}

const SportLeaguePage = ({
    league,
    title,
    subTitle,
    games,
    favoriteGames,
    followedTitle = "Followed Teams",
    gamesTitle = `Today's ${title} Games`,
}: SportLeaguePageProps) => {
    return (
        <>
        <SportsLayout title={title} subTitle={subTitle} league={league}>
            <FilteredSportsContainer
                className="games-list"
                title={followedTitle}
                type={league}
            >
                {favoriteGames.map((gameCard) => (
                    <HorizontalGameCard 
                        game={gameCard}
                    />
                ))}
            </FilteredSportsContainer>

            <FilteredSportsContainer
                className="games-list"
                title={gamesTitle}
                type={league}
            >
                {games.map((gameCard) => (
                    <HorizontalGameCard
                        key={String(gameCard.id ?? gameCard.title)}
                        className="horizontal-card"
                        game={gameCard}
                    />
                ))}
            </FilteredSportsContainer>
        </SportsLayout>
        </>
    );
};

export default SportLeaguePage;