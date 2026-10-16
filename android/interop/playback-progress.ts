/** Shared v1 Firestore contract; adapters accept seconds (never milliseconds). */
export interface PlaybackProgress {
  progressVersion: 1;
  mediaId: number;
  mediaType: 'movie' | 'tv';
  season: number;
  episode: number;
  positionSeconds: number;
  durationSeconds: number;
}
export function progressDocumentId(p: Pick<PlaybackProgress, 'mediaType' | 'mediaId'>): string {
  return `${p.mediaType}-${p.mediaId}`;
}
export function validatedProgress(p: PlaybackProgress): PlaybackProgress | undefined {
  if (p.progressVersion !== 1 || !Number.isInteger(p.mediaId) || p.mediaId <= 0 || !['movie', 'tv'].includes(p.mediaType)
      || !Number.isInteger(p.season) || p.season < 1 || !Number.isInteger(p.episode) || p.episode < 1
      || !Number.isFinite(p.durationSeconds) || p.durationSeconds < 60 || p.durationSeconds > 43200
      || !Number.isFinite(p.positionSeconds) || p.positionSeconds < 0 || p.positionSeconds > p.durationSeconds + 5) return;
  return {...p, positionSeconds: Math.min(p.positionSeconds, p.durationSeconds)};
}
export function resumePosition(p: PlaybackProgress, season = 1, episode = 1): number {
  const valid = validatedProgress(p);
  return valid && valid.season === season && valid.episode === episode && valid.positionSeconds >= 5
    && valid.positionSeconds / valid.durationSeconds < .95 ? valid.positionSeconds : 0;
}
export function progressFraction(p: PlaybackProgress): number {
  const valid = validatedProgress(p);
  return valid ? valid.positionSeconds / valid.durationSeconds : 0;
}
