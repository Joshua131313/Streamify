import type { TMDBCastPerson } from "../../../types/TMDBMediaType";
import { CreditsList } from "./CreditsList";

interface Props {
    cast: TMDBCastPerson[] | undefined;
}

export const Cast = ({ cast }: Props) => {
    return (
        <CreditsList
            items={cast}
            title="Actors"
            containerId="cast"
            className="cast"
            getKey={(person) => person.id}
            getName={(person) => person.name}
            getSubtitle={(person) => person.character}
            getProfilePath={(person) => person.profile_path}
            getId={(person) => person.id}
        />
    );
};