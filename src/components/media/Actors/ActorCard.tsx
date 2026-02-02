import type { TMDBCastPerson } from "../../../types/TMDBMediaType"
import { TMDBImg } from "../../ui/TMDBImg/TMDBImg";
import "./Actors.css"

interface Props {
    actor: TMDBCastPerson;
}

export const ActorCard = (props: Props) => {
    const { actor } = props;

    return (
        <a target="_blank" href={`https://www.google.com/search?q=${actor.name}`}>
            <div className="actor-card">
                <TMDBImg path={actor.profile_path} />
                <div className="actor-info">
                    <strong>{actor.name}</strong>
                    <small>{actor.character}</small>
                </div>
            </div>
        </a>
    )
}