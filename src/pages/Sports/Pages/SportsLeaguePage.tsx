import SportsLayout from "../SportsLayout";
import type { Leagues } from "../../../types/sports/sportsTypes";
import { SportCardsViewFactory } from "../../../components/sports/SportCardsViews/SportCardsViewFactory";
import type { SportDisplayGame } from "../../../types/sports/sportsDisplayTypes";

interface SportLeaguePageProps {
    league: Leagues;
    title: string;
    subTitle: string;
    games: SportDisplayGame[];
    favoriteGames: SportDisplayGame[];
    followedTitle?: string;
    gamesTitle?: string;
    gamesLoading: boolean;
}

const SportLeaguePage = ({
    league,
    title,
    subTitle,
    games,
    favoriteGames,
    followedTitle = "Followed Teams",
    gamesTitle = `Today's ${title} Games`,
    gamesLoading
}: SportLeaguePageProps) => {
    return (
        <>
            <SportsLayout title={title} subTitle={subTitle} league={league}>
                {
                    favoriteGames.length !== 0 &&
                    <SportCardsViewFactory
                        games={favoriteGames}
                        gamesLoading={false}
                        title={followedTitle}
                        type={league}
                    />
                }
                <SportCardsViewFactory
                    games={games}
                    gamesLoading={gamesLoading}
                    title={gamesTitle}
                    type={league}
                />
            </SportsLayout>
        </>
    );
};

export default SportLeaguePage;