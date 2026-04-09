import { useSports } from "../../../context/SportsContext";
import SportLeaguePage from "./SportsLeaguePage";

const MLB = () => {
    const { mlbGameCards, favoriteMLBGameCards } = useSports();

    return (
        <SportLeaguePage
            league="MLB"
            title="MLB"
            subTitle="Browse live MLB games"
            games={mlbGameCards}
            favoriteGames={favoriteMLBGameCards}
        />
    );
};

export default MLB;