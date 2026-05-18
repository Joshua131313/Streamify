import "./Sports.css";
import { useSports } from "../../context/SportsContext";
import { AppSwiper } from "../../components/ui/AppSwiper/AppSwiper";
import { channelStreams } from "../../data/sports/sportsData";
import { ChannelCard } from "../../components/ui/ChannelCard/ChannelCard";
import SportsLayout from "./SportsLayout";
import { FilteredSportsContainer } from "../../components/layout/Container/FilteredSportsContainer";
import { SportCardsViewFactory } from "../../components/sports/SportCardsViews/SportCardsViewFactory";
import { MediaSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/MediaSkeletonCard";

const Sports = () => {
    const {
        nbaGamesLoading,
        wnbaGamesLoading,
        nhlGamesLoading,
        mlbGamesLoading,
        nbaGameCards,
        wnbaGameCards,
        nhlGameCards,
        mlbGameCards,
        favoriteGameCards,
        layout
    } = useSports();

    return (
        <SportsLayout title="Sports" subTitle="Browse live sports" league="all" >
            {
                favoriteGameCards.length !== 0 &&
                <SportCardsViewFactory
                    games={favoriteGameCards}
                    gamesLoading={false}
                    title="Followed Teams"
                    type="FOLLOW"
                />
            }
            <FilteredSportsContainer type="TV" title="Sports Channels">
                <AppSwiper
                    items={channelStreams}
                    itemKey={(item) => item.title}
                    renderItem={(stream) => (
                        <ChannelCard stream={stream} />
                    )}
                    skeleton={<MediaSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>
            <SportCardsViewFactory
                games={nbaGameCards}
                gamesLoading={nbaGamesLoading}
                title="NBA"
                type="NBA"
            />
            <SportCardsViewFactory
                games={wnbaGameCards}
                gamesLoading={wnbaGamesLoading}
                title="WNBA"
                type="WNBA"
            />
            <SportCardsViewFactory
                games={nhlGameCards}
                gamesLoading={nhlGamesLoading}
                title="NHL"
                type="NHL"
            />
            <SportCardsViewFactory
                games={mlbGameCards}
                gamesLoading={mlbGamesLoading}
                title="MLB"
                type="MLB"
            />
        </SportsLayout>

    );
};

export default Sports;