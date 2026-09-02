import { JSON } from '@kit.ArkTS';
import { ChaoXingApi} from './PublicAPI'
import { ChaoxingUtils } from './utils';
import { Http } from './httpClient';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'CourseActivityService';
const DOMAIN = 0x0003;
export interface ActivityInfo {
  ActivityId: number;
  CourseId: number;
  ClassId: number;
  signType: string
}
export class CourseAndActivity {
  /**
   * 获取课程列表，需要cookies
   * @param cookies
   * @returns
   */
  static async getClassList(cookies: string): Promise<returnJson> {
    try {
      const CourseListResponse = await Http.getJson(ChaoXingApi.URL_GET_COURSE_LIST, cookies) as CourseListResponse
      if (CourseListResponse.msg === "获取成功") {
        const courseList = CourseListResponse.channelList
        const result: ClassInfo[] = [];

        courseList.forEach(item => {
          // 检查 content 和 course.data 是否存在
          if (item.content && item.content.course && item.content.course.data) {
            item.content.course.data.forEach(course => {
              result.push({
                imageURL: course.imageurl,
                id: course.id, // 课程id
                teacherfactor: course.teacherfactor,
                classId: item.content.id, // 班级id
                name: course.name
              });
            });
          }
        });

        hilog.info(DOMAIN, TAG, `Successfully fetched ${result.length} classes`);
        return { msg: true, classList: result };
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get class list: ${error.message}`);
    }
    return {
      msg: false,
      classList:
      [
        {
          imageURL: '',
          id: '',
          teacherfactor: '',
          classId: '',
          name: ''
        }
      ]
    }
  }

  /**
   * 校验用户是否在指定班级（对齐上游 ChaoxingCourseHelper.checkClassValid）
   * 逐项比对课程频道列表的班级 id（content.id），与该频道是否包含课程数据无关
   * @returns true=在班级 false=不在班级 null=无法判定（接口异常或返回异常）
   */
  static async checkClassValid(cookies: string, classId: string): Promise<boolean | null> {
    try {
      const jsonResult = await Http.getJson(ChaoXingApi.URL_GET_COURSE_LIST, cookies) as CourseListResponse;
      const channelList = jsonResult.channelList;
      if (jsonResult.result === 0 || !channelList) {
        return null;
      }
      for (const channel of channelList) {
        if (channel.content && String(channel.content.id) === String(classId)) {
          return true;
        }
      }
      return false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Check class valid failed: ${error.message}`);
      return null;
    }
  }

  static async getActivityList(cookies: string, classId: string, courseId: string): Promise<ActivityListResult | null> {
    const url = ChaoxingUtils.buildUrl(ChaoXingApi.URL_GET_ACTIVITY_LIST,
      {
        'classId': classId,
        'courseId': courseId
      })
    hilog.debug(DOMAIN, TAG, 'Fetching activity list');
    try {
      const ActivityMessage = await Http.getJson(url, cookies)
      const data = ActivityMessage?.['data'] as object
      const ActivityList = data?.['activeList'] as ActivityItem[]
      const ext = data?.['ext'] as object
      return {
        ext: ext ? JSON.stringify(ext) : '',
        activities: ActivityList
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get activity list: ${error.message}`);
      return null
    }
  }
}

export interface ActivityListResult {
  /** 活动列表接口返回的 data.ext 原样字符串，preSign 时需要 */
  ext: string;
  activities: ActivityItem[];
}

export interface ActivityItem {
  /** 签到类型ID，用于识别签到方式 */
  otherId: number;

  /** 活动类型，用于过滤显示（2=签到, 74=签退） */
  type: number;

  /** 签到类型名称，如"位置签到"、"二维码签到"等 */
  nameOne: string;

  /** 活动开始时间戳，用于判断签到是否开始和计算剩余时间 */
  startTime: number;

  /** 活动ID，用于页面导航参数传递 */
  id: string;

  /** 活动结束时间戳，用于判断签到是否结束和控制UI状态 */
  endTime: number;
}
export interface ClassInfo {
  imageURL: string;
  id: string; // 课程id
  teacherfactor: string;
  classId: string; // 班级id
  name: string;
}


// 课程频道项目接口
export interface CourseChannel {
  /** 分类ID */
  cataid: string;

  /** 项目ID */
  id: number;

  /** 班级唯一标识符 */
  key: number | string;

  /** 课程内容详情 */
  content: CourseContent;

  /** 置顶标记 */
  topsign: number;
}

// 班级/课程内容接口
export interface CourseContent {
  /** 班级名称 */
  name: string;

  /** 课程数据 */
  course: Data;

  /** 班级ID */
  id: string;
}

// 课程基本信息接口
export interface CourseInfo {
  /** 课程ID */
  id: string;

  /** 课程名称 */
  name: string;

  /** 授课教师 */
  teacherfactor: string;

  /** 创建时间戳 */
  createtime: number;

  /** 课程图片URL */
  imageurl: string;

  /** 课程状态 */
  coursestate: number;
}

// 课程列表响应接口
export interface CourseListResponse {
  /** 响应结果：1=成功 */
  result: number;

  /** 响应消息 */
  msg: string;

  /** 课程频道列表 */
  channelList: CourseChannel[];

  /** 教师结课状态 */
  teacherEndCourse: number;

  /** 显示结课状态 */
  showEndCourse: number;

  /** 学生结课状态 */
  stuEndCourse: number;
}

export interface Data {
  data: CourseInfo[]
}

export interface returnJson {
  msg: boolean;
  classList: ClassInfo[];
}
