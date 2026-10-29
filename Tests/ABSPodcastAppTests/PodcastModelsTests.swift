@testable import ABSPodcastApp
import Foundation
import Testing

struct PodcastModelsTests {
    private func detail() throws -> PodcastDetail {
        try JSONDecoder().decode(PodcastDetail.self, from: Data(Fixture.podcastDetail.utf8))
    }

    @Test func episodesSortNewestFirstWithAddedAtFallback() throws {
        #expect(try detail().episodesNewestFirst.map(\.id) == ["ep_new", "ep_undated", "ep_old"])
    }

    @Test func episodeWithMostlyNullFieldsDecodes() throws {
        let undated = try #require(try detail().media.episodes.first { $0.id == "ep_undated" })
        #expect(undated.publishedDate == nil)
        #expect(undated.duration == nil)
        #expect(undated.season == nil)
    }

    @Test func unknownLibraryTypeDecodesAsOther() throws {
        let response = try JSONDecoder().decode(LibrariesResponse.self, from: Data(Fixture.libraries.utf8))
        #expect(response.libraries.first { $0.id == "lib_future" }?.mediaType == .other("comic"))
    }
}

struct EpisodeProgressTests {
    private func record(
        progress: Double? = nil,
        currentTime: Double? = nil,
        duration: Double? = nil,
        finished: Bool = false
    ) -> MediaProgress {
        MediaProgress(
            libraryItemId: "li_1",
            episodeId: "ep",
            duration: duration,
            progress: progress,
            currentTime: currentTime,
            isFinished: finished
        )
    }

    @Test func noRecordIsUnplayed() {
        #expect(EpisodeProgress(nil, episodeDuration: 100) == .unplayed)
    }

    @Test func finishedWinsOverPosition() {
        #expect(EpisodeProgress(record(progress: 0.3, currentTime: 30, finished: true), episodeDuration: 100) == .finished)
    }

    @Test func zeroRecordedDurationFallsBackToEpisodeDuration() {
        let state = EpisodeProgress(record(progress: 0.5, currentTime: 2700, duration: 0), episodeDuration: 5400)
        #expect(state == .inProgress(fraction: 0.5, remaining: 2700))
    }

    @Test func missingFractionIsComputedFromTime() {
        let state = EpisodeProgress(record(currentTime: 25, duration: 100), episodeDuration: nil)
        #expect(state == .inProgress(fraction: 0.25, remaining: 75))
    }

    @Test func unknownLengthHasNoRemainingTime() {
        #expect(EpisodeProgress(record(progress: 0.4, currentTime: 10), episodeDuration: nil) == .inProgress(fraction: 0.4, remaining: nil))
    }

    @Test func zeroPositionIsUnplayed() {
        #expect(EpisodeProgress(record(progress: 0, currentTime: 0, duration: 100), episodeDuration: 100) == .unplayed)
    }

    @Test func indexOnlyMatchesThisPodcastsEpisodes() throws {
        let records = try JSONDecoder().decode(MediaProgressResponse.self, from: Data(Fixture.progress.utf8)).mediaProgress
        let episodes = try JSONDecoder().decode(PodcastDetail.self, from: Data(Fixture.podcastDetail.utf8)).media.episodes
        let index = EpisodeProgressIndex(records, libraryItemId: "li_1")

        let states = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, index.progress(for: $0)) })
        #expect(states["ep_new"] == .inProgress(fraction: 0.5, remaining: 2700))
        #expect(states["ep_old"] == .finished)
        // ep_undated only has progress under a different podcast.
        #expect(states["ep_undated"] == .unplayed)
    }
}

struct PlainTextTests {
    @Test func stripsTagsKeepsParagraphsAndDecodesEntities() {
        let html = "<p>Tom &amp; Jerry&rsquo;s <b>show</b></p><p>Line one<br/>line two</p>"
        #expect(PlainText.from(html: html) == "Tom & Jerry\u{2019}s show\n\nLine one\nline two")
    }

    @Test func plainTextPassesThrough() {
        #expect(PlainText.from(html: "  Just words.  ") == "Just words.")
    }
}
