<script>
  import { mapActions, mapGetters, mapState } from 'vuex';
  import { s__ } from '~/locale';
  import { componentNames } from './issue_body';
  import ReportSection from './report_section.vue';
  import SummaryRow from './summary_row.vue';
  import IssuesList from './issues_list.vue';
  import Modal from './modal.vue';
  import createStore from '../store';
  import { summaryTextBuilder, reportTextBuilder, statusIcon } from '../store/utils';

  export default {
    name: 'GroupedTestReportsApp',
    store: createStore(),
    components: {
      ReportSection,
      SummaryRow,
      IssuesList,
      Modal,
    },
    props: {
      endpoint: {
        type: String,
        required: true,
      },
    },
    componentNames,
    computed: {
      ...mapState([
        'reports',
        'isLoading',
        'hasError',
        'summary',
      ]),
      ...mapState({
        modalTitle: state => state.modal.title || '',
        modalData: state => state.modal.data || {},
      }),
      ...mapGetters([
        'summaryStatus',
      ]),
      groupedSummaryText() {
        if (this.isLoading) {
          return s__('Reports|Test summary results are being parsed');
        }

        if (this.hasError) {
          return s__('Reports|Test summary failed loading results');
        }

        return summaryTextBuilder(s__('Reports|Test summary'), this.summary);
      },
    },
    created() {
      this.setEndpoint(this.endpoint);

      this.fetchReports();
    },
    methods: {
      ...mapActions(['setEndpoint', 'fetchReports']),
      reportText(report) {
        const summary = report.summary || {};
        return reportTextBuilder(report.name, summary);
      },
      getReportIcon(report) {
        return statusIcon(report.status);
      },
      shouldRenderIssuesList(report) {
        return (
          report.existing_failures.length > 0 ||
          report.new_failures.length > 0 ||
          report.resolved_failures.length > 0
        );
      },
    },
  };
</script>
<template>
  <report-section
    :status="summaryStatus"
    :success-text="groupedSummaryText"
    :loading-text="groupedSummaryText"
    :error-text="groupedSummaryText"
    :has-issues="reports.length > 0"
    class="mr-widget-section grouped-security-reports mr-report"
  >
    <div
      slot="body"
      class="mr-widget-grouped-section report-block"
    >
      <template
        v-for="(report, i) in reports"
      >
        <summary-row
          :key="`summary-row-${i}`"
          :summary="reportText(report)"
          :status-icon="getReportIcon(report)"
        />
        <issues-list
          v-if="shouldRenderIssuesList(report)"
          :key="`issues-list-${i}`"
          :unresolved-issues="report.existing_failures"
          :new-issues="report.new_failures"
          :resolved-issues="report.resolved_failures"
          :component="$options.componentNames.TestIssueBody"
          class="report-block-group-list"
        />
      </template>

      <modal
        :title="modalTitle"
        :modal-data="modalData"
      />
    </div>
  </report-section>
</template>
