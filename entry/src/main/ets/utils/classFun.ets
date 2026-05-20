import { http } from '@kit.NetworkKit';
import { ChaoXingApi} from './PublicAPI'
import { DatabaseManager } from './DataBase';
import { ChaoxingUtils } from './utils';
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
    const httpRequest = http.createHttp();
    try {
      const result = await httpRequest.request(ChaoXingApi.URL_GET_COURSE_LIST, {
        method: http.RequestMethod.GET,
        header: {
          "Cookie": cookies
        }
      })
      const CourseListResponse = JSON.parse(result.result.toString()) as CourseListResponse
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
    } finally {
      httpRequest.destroy()
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

  static async getActivityList(cookies: string, classId: string, courseId: string): Promise<ActivityItem[]|null> {
    const httpRequest = http.createHttp();
    const url=ChaoxingUtils.buildUrl(ChaoXingApi.URL_GET_ACTIVITY_LIST,
      {
        'classId': classId,
        'courseId': courseId
      })
    hilog.debug(DOMAIN, TAG, 'Fetching activity list');
    try {
      const result = await httpRequest.request(url,
        {
          method: http.RequestMethod.GET,
          header: {
            "Cookie": cookies
          }
        })
      const ActivityMessage = JSON.parse(result.result.toString()) as object
      const ActivityList = ActivityMessage?.['data']?.['activeList'] as ActivityItem[]
      return ActivityList
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get activity list: ${error.message}`);
      return null
    }finally {
      httpRequest.destroy()
    }
  }
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
