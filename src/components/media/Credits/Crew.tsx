import type { TMDBCrewPerson } from "../../../types/TMDBMediaType";
import { CreditsList } from "./CreditsList";

interface Props {
  crew: TMDBCrewPerson[] | undefined;
}

export const Crew = ({ crew }: Props) => {
  return (
    <CreditsList
      items={crew}
      title="Crew" 
      containerId="crew"
      className="crew"
      getKey={(person) => `${person.id}-${person.job}`}
      getName={(person) => person.name}
      getSubtitle={(person) => person.job}
      getProfilePath={(person) => person.profile_path}
    />
  );
};