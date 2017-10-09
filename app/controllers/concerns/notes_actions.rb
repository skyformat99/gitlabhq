module NotesActions
  include RendersNotes
  extend ActiveSupport::Concern

  included do
    before_action :set_polling_interval_header, only: [:index]
    before_action :authorize_admin_note!, only: [:update, :destroy]
    before_action :note_project, only: [:create]
  end

  def index
    current_fetched_at = Time.now.to_i

    notes_json = { notes: [], last_fetched_at: current_fetched_at }

    notes = notes_finder.execute
      .inc_relations_for_view

    notes = prepare_notes_for_rendering(notes)
    notes = notes.reject { |n| n.cross_reference_not_visible_for?(current_user) }

    notes_json[:notes] =
      if noteable.discussions_rendered_on_frontend?
        note_serializer.represent(notes)
      else
        notes.map { |note| note_json(note) }
      end

    render json: notes_json
  end

  def create
    create_params = note_params.merge(
      merge_request_diff_head_sha: params[:merge_request_diff_head_sha],
      in_reply_to_discussion_id: params[:in_reply_to_discussion_id]
    )

    @note = Notes::CreateService.new(note_project, current_user, create_params).execute

    if @note.is_a?(Note)
      Banzai::NoteRenderer.render([@note], @project, current_user)
    end

    respond_to do |format|
      format.json { render json: note_json(@note) }
      format.html { redirect_back_or_default }
    end
  end

  def update
    @note = Notes::UpdateService.new(project, current_user, note_params).execute(note)

    if @note.is_a?(Note)
      Banzai::NoteRenderer.render([@note], @project, current_user)
    end

    respond_to do |format|
      format.json { render json: note_json(@note) }
      format.html { redirect_back_or_default }
    end
  end

  def destroy
    if note.editable?
      Notes::DestroyService.new(project, current_user).execute(note)
    end

    respond_to do |format|
      format.js { head :ok }
    end
  end

  private

  def note_html(note)
    render_to_string(
      "shared/notes/_note",
      layout: false,
      formats: [:html],
      locals: { note: note }
    )
  end

  def note_json(note)
    attrs = {
      commands_changes: note.commands_changes
    }

    if note.persisted?
      attrs[:valid] = true

      if noteable.nil? || noteable.discussions_rendered_on_frontend?
        attrs.merge!(note_serializer.represent(note))
      else
        attrs.merge!(
          id: note.id,
          discussion_id: note.discussion_id(noteable),
          html: note_html(note),
          note: note.note,
          on_image: note.try(:on_image?)
        )

        discussion = note.to_discussion(noteable)
        unless discussion.individual_note?
          attrs.merge!(
            discussion_resolvable: discussion.resolvable?,

            diff_discussion_html: diff_discussion_html(discussion),
            discussion_html: discussion_html(discussion)
          )
        end
      end
    else
      attrs.merge!(
        valid: false,
        errors: note.errors
      )
    end

    attrs
  end

  def diff_discussion_html(discussion)
    return unless discussion.diff_discussion?

    on_image = discussion.on_image?

    if params[:view] == 'parallel' && !on_image
      template = "discussions/_parallel_diff_discussion"
      locals =
        if params[:line_type] == 'old'
          { discussions_left: [discussion], discussions_right: nil }
        else
          { discussions_left: nil, discussions_right: [discussion] }
        end
    else
      template = "discussions/_diff_discussion"
      @fresh_discussion = true

      locals = { discussions: [discussion], on_image: on_image }
    end

    render_to_string(
      template,
      layout: false,
      formats: [:html],
      locals: locals
    )
  end

  def discussion_html(discussion)
    return if discussion.individual_note?

    render_to_string(
      "discussions/_discussion",
      layout: false,
      formats: [:html],
      locals: { discussion: discussion }
    )
  end

  def authorize_admin_note!
    return access_denied! unless can?(current_user, :admin_note, note)
  end

  def note_params
    params.require(:note).permit(
      :project_id,
      :noteable_type,
      :noteable_id,
      :commit_id,
      :noteable,
      :type,

      :note,
      :attachment,

      # LegacyDiffNote
      :line_code,

      # DiffNote
      :position
    )
  end

  def set_polling_interval_header
    Gitlab::PollingInterval.set_header(response, interval: 6_000)
  end

  def noteable
    @noteable ||= notes_finder.target
  end

  def last_fetched_at
    request.headers['X-Last-Fetched-At']
  end

  def notes_finder
    @notes_finder ||= NotesFinder.new(project, current_user, finder_params)
  end

  def note_serializer
    NoteSerializer.new(project: project, noteable: noteable, current_user: current_user)
  end

  def note_project
    return @note_project if defined?(@note_project)
    return nil unless project

    note_project_id = params[:note_project_id]

    @note_project =
      if note_project_id.present?
        Project.find(note_project_id)
      else
        project
      end

    return access_denied! unless can?(current_user, :create_note, @note_project)

    @note_project
  end
end
