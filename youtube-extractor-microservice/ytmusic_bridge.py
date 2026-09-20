#!/usr/bin/env python3
import json
import os
import sys
from typing import Any

from ytmusicapi import YTMusic


def thumbnail(item: dict[str, Any]) -> str | None:
    thumbnails = item.get("thumbnails") or []
    if not thumbnails:
        return None
    return thumbnails[-1].get("url")


def artists(item: dict[str, Any]) -> str:
    values = item.get("artists") or []
    names = [value.get("name", "") for value in values if value.get("name")]
    return ", ".join(names) or item.get("author", "YouTube Artist")


def normalize_search_item(item: dict[str, Any]) -> dict[str, Any] | None:
    video_id = item.get("videoId")
    if not video_id:
        return None
    image = thumbnail(item)
    return {
        "id": video_id,
        "youtubeId": video_id,
        "title": item.get("title") or "YouTube Track",
        "artist": artists(item),
        "channelTitle": item.get("author"),
        "album": (item.get("album") or {}).get("name") if isinstance(item.get("album"), dict) else "YouTube Music",
        "duration": item.get("duration_seconds") or 0,
        "thumbnail": image,
        "artworkUrl": image,
        "streamUrl": f"https://www.youtube.com/watch?v={video_id}",
    }


def song_metadata(ytmusic: YTMusic, video_id: str) -> dict[str, Any] | None:
    data = ytmusic.get_song(video_id)
    details = data.get("videoDetails") or {}
    returned_id = details.get("videoId")
    if returned_id != video_id:
        return None
    image = None
    thumbnails = (details.get("thumbnail") or {}).get("thumbnails") or []
    if thumbnails:
        image = thumbnails[-1].get("url")
    return {
        "source": "youtube",
        "videoId": video_id,
        "requestedVideoId": video_id,
        "title": details.get("title") or "YouTube Audio",
        "artist": details.get("author") or "YouTube Artist",
        "duration": int(details.get("lengthSeconds") or 0),
        "thumbnailUrl": image or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
        "mediaState": "MetadataResolved",
    }


def main() -> None:
    if len(sys.argv) < 2:
        raise ValueError("operation is required")
    operation = sys.argv[1]
    ytmusic = YTMusic(os.environ.get("YTMUSICAPI_AUTH_JSON") or None)

    if operation == "search":
        query = sys.argv[2]
        limit = min(int(sys.argv[3]), 50)
        items = ytmusic.search(query, filter="songs", limit=limit)
        results = [item for item in (normalize_search_item(value) for value in items) if item]
        print(json.dumps({"source": "ytmusicapi", "results": results}))
        return

    if operation == "song":
        video_id = sys.argv[2]
        result = song_metadata(ytmusic, video_id)
        print(json.dumps(result or {}))
        return

    raise ValueError(f"unsupported operation: {operation}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": type(exc).__name__, "message": str(exc)}))
        sys.exit(1)
